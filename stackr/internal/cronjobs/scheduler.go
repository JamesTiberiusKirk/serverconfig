package cronjobs

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"

	cron "github.com/robfig/cron/v3"
	"gopkg.in/yaml.v3"

	"serverconfig/stackr/internal/config"
	"serverconfig/stackr/internal/runner"
	"serverconfig/stackr/internal/stackcmd"
)

const (
	scheduleLabel    = "stackr.cron.schedule"
	runOnDeployLabel = "stackr.cron.run_on_deploy"
)

type Scheduler struct {
	mu   sync.Mutex
	cron *cron.Cron
	jobs []cronJob
	cfg  config.Config
}

type cronJob struct {
	Stack       string
	Service     string
	Schedule    string
	Profile     string
	RunOnDeploy bool
	ComposeFile string
}

type composeFile struct {
	Services map[string]composeService `yaml:"services"`
}

type composeService struct {
	Labels   labelMap `yaml:"labels"`
	Profiles []string `yaml:"profiles"`
}

type labelMap map[string]string

func (l *labelMap) UnmarshalYAML(value *yaml.Node) error {
	result := make(map[string]string)
	if value == nil || value.Kind == 0 {
		*l = result
		return nil
	}

	switch value.Kind {
	case yaml.SequenceNode:
		for _, item := range value.Content {
			parts := strings.SplitN(item.Value, "=", 2)
			if len(parts) != 2 {
				continue
			}
			result[strings.TrimSpace(parts[0])] = strings.TrimSpace(parts[1])
		}
	case yaml.MappingNode:
		for i := 0; i < len(value.Content); i += 2 {
			key := strings.TrimSpace(value.Content[i].Value)
			if i+1 >= len(value.Content) {
				continue
			}
			result[key] = strings.TrimSpace(value.Content[i+1].Value)
		}
	default:
		return fmt.Errorf("unsupported labels format: %s", value.ShortTag())
	}

	*l = result
	return nil
}

func New(cfg config.Config) (*Scheduler, error) {
	jobs, err := discoverJobs(cfg)
	if err != nil {
		return nil, err
	}

	return &Scheduler{
		jobs: jobs,
		cfg:  cfg,
	}, nil
}

func (s *Scheduler) Start() error {
	if s == nil {
		return nil
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	if s.cron != nil {
		return nil
	}

	return s.startLocked()
}

func (s *Scheduler) Reload() error {
	if s == nil {
		return nil
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	jobs, err := discoverJobs(s.cfg)
	if err != nil {
		return err
	}

	if s.cron != nil {
		ctx := s.cron.Stop()
		<-ctx.Done()
		s.cron = nil
	}

	s.jobs = jobs
	return s.startLocked()
}

func (s *Scheduler) Stop() {
	if s == nil {
		return
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	if s.cron == nil {
		return
	}

	ctx := s.cron.Stop()
	<-ctx.Done()
	s.cron = nil
}

func (s *Scheduler) startLocked() error {
	if len(s.jobs) == 0 {
		log.Printf("no cron-enabled services detected")
		return nil
	}

	logger := cron.PrintfLogger(log.New(os.Stdout, "cron: ", log.LstdFlags))
	parser := cron.NewParser(cron.Minute | cron.Hour | cron.Dom | cron.Month | cron.Dow | cron.Descriptor)
	c := cron.New(cron.WithParser(parser), cron.WithChain(cron.SkipIfStillRunning(logger)))

	for _, job := range s.jobs {
		jobCfg := job
		if _, err := parser.Parse(jobCfg.Schedule); err != nil {
			return fmt.Errorf("invalid cron schedule for stack=%s service=%s: %w", jobCfg.Stack, jobCfg.Service, err)
		}

		if _, err := c.AddFunc(jobCfg.Schedule, func() { s.execute(jobCfg) }); err != nil {
			return fmt.Errorf("failed to schedule cron job for stack=%s service=%s: %w", jobCfg.Stack, jobCfg.Service, err)
		}

		log.Printf("scheduled cron job stack=%s service=%s schedule=%q", jobCfg.Stack, jobCfg.Service, jobCfg.Schedule)

		if jobCfg.RunOnDeploy {
			go func(j cronJob) {
				log.Printf("run-on-deploy cron job triggered stack=%s service=%s", j.Stack, j.Service)
				s.execute(j)
			}(jobCfg)
		}
	}

	c.Start()
	s.cron = c
	log.Printf("cron scheduler started with %d job(s)", len(s.jobs))
	return nil
}

func discoverJobs(cfg config.Config) ([]cronJob, error) {
	entries, err := os.ReadDir(cfg.StacksDir)
	if err != nil {
		return nil, fmt.Errorf("failed to read stacks dir %s: %w", cfg.StacksDir, err)
	}

	var jobs []cronJob
	for _, entry := range entries {
		if !entry.IsDir() {
			continue
		}

		stackName := entry.Name()
		composePath := filepath.Join(cfg.StacksDir, stackName, "docker-compose.yml")
		content, err := os.ReadFile(composePath)
		if err != nil {
			if errors.Is(err, os.ErrNotExist) {
				continue
			}
			return nil, fmt.Errorf("failed to read %s: %w", composePath, err)
		}

		var parsed composeFile
		if err := yaml.Unmarshal(content, &parsed); err != nil {
			return nil, fmt.Errorf("failed to parse %s: %w", composePath, err)
		}

		for serviceName, service := range parsed.Services {
			schedule := strings.TrimSpace(service.Labels[scheduleLabel])
			if schedule == "" {
				continue
			}

			profile := ""
			if len(service.Profiles) == 1 {
				profile = strings.TrimSpace(service.Profiles[0])
			}

			runOnDeploy := false
			if raw := strings.TrimSpace(service.Labels[runOnDeployLabel]); raw != "" {
				parsed, err := strconv.ParseBool(raw)
				if err != nil {
					log.Printf("invalid %s value for stack=%s service=%s: %q", runOnDeployLabel, stackName, serviceName, raw)
				} else {
					runOnDeploy = parsed
				}
			}

			jobs = append(jobs, cronJob{
				Stack:       stackName,
				Service:     serviceName,
				Schedule:    schedule,
				Profile:     profile,
				RunOnDeploy: runOnDeploy,
				ComposeFile: composePath,
			})
		}
	}

	return jobs, nil
}

func (s *Scheduler) execute(job cronJob) {
	ctx, cancel := context.WithTimeout(context.Background(), runner.CommandTimeout)
	defer cancel()

	var stdout bytes.Buffer
	var stderr bytes.Buffer
	manager, err := stackcmd.NewManagerWithWriters(s.cfg, &stdout, &stderr)
	if err != nil {
		log.Printf("cron job failed to create manager stack=%s service=%s: %v",
			job.Stack, job.Service, err)
		return
	}

	composeArgs := []string{"docker", "compose", "--file", job.ComposeFile}
	if profile := strings.TrimSpace(job.Profile); profile != "" {
		composeArgs = append(composeArgs, "--profile", profile)
	}
	composeArgs = append(composeArgs, "run", "--rm", job.Service)

	opts := stackcmd.Options{
		Stacks:      []string{job.Stack},
		VarsOnly:    true,
		VarsCommand: composeArgs,
	}

	log.Printf("cron job started stack=%s service=%s", job.Stack, job.Service)
	if err := manager.Run(ctx, opts); err != nil {
		log.Printf("cron job failed stack=%s service=%s\nstdout: %s\nstderr: %s",
			job.Stack,
			job.Service,
			strings.TrimSpace(stdout.String()),
			strings.TrimSpace(stderr.String()),
		)
		return
	}

	output := strings.TrimSpace(stdout.String())
	if output == "" {
		log.Printf("cron job finished stack=%s service=%s", job.Stack, job.Service)
		return
	}

	log.Printf("cron job finished stack=%s service=%s output=%s", job.Stack, job.Service, output)
}
