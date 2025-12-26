package config

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"

	"gopkg.in/yaml.v3"
)

type StackConfig struct {
	TagEnv string
	Args   []string
}

type Config struct {
	Token     string
	EnvFile   string
	Host      string
	Port      string
	RepoRoot  string
	StacksDir string
	Global    GlobalConfig
}

type GlobalConfig struct {
	Path     string                 `yaml:"-"`
	Stacks   string                 `yaml:"stacks_dir"`
	Cron     CronConfig             `yaml:"cron"`
	HTTP     HTTPConfig             `yaml:"http"`
	Paths    PathsConfig            `yaml:"paths"`
	Deploy   map[string]StackDeploy `yaml:"deploy"`
	Env      EnvConfig              `yaml:"env"`
}

type CronConfig struct {
	DefaultProfile string `yaml:"profile"`
}

type HTTPConfig struct {
	BaseDomain string `yaml:"base_domain"`
}

type PathsConfig struct {
	BackupDir string            `yaml:"backup_dir"`
	Pools     map[string]string `yaml:"pools"`
	Custom    map[string]string `yaml:"custom"`
}

type StackDeploy struct {
	TagEnv string   `yaml:"tag_env"`
	Args   []string `yaml:"args"`
}

type EnvConfig struct {
	Global map[string]string            `yaml:"global"`
	Stacks map[string]map[string]string `yaml:"stacks"`
}

const defaultGlobalConfig = ".stackr.yaml"

func ResolveRepoRoot(override string) (string, error) {
	override = strings.TrimSpace(override)
	if override == "" {
		return determineRepoRoot()
	}

	if !filepath.IsAbs(override) {
		abs, err := filepath.Abs(override)
		if err != nil {
			return "", fmt.Errorf("failed to resolve STACKR_REPO_ROOT: %w", err)
		}
		override = abs
	}

	info, err := os.Stat(override)
	if err != nil {
		return "", fmt.Errorf("STACKR_REPO_ROOT: %w", err)
	}

	if !info.IsDir() {
		return "", errors.New("STACKR_REPO_ROOT must point to a directory")
	}

	return override, nil
}

func Load(repoRoot string) (Config, error) {
	return loadConfig(repoRoot, true)
}

func LoadForCLI(repoRoot string) (Config, error) {
	return loadConfig(repoRoot, false)
}

func loadConfig(repoRoot string, requireToken bool) (Config, error) {
	globalCfg, globalPath, err := loadGlobalConfig(repoRoot)
	if err != nil {
		return Config{}, err
	}
	globalCfg.Path = globalPath

	token := strings.TrimSpace(os.Getenv("STACKR_TOKEN"))
	if token == "" && requireToken {
		return Config{}, errors.New("STACKR_TOKEN is required")
	}

	envFile := strings.TrimSpace(os.Getenv("STACKR_ENV_FILE"))
	if envFile == "" {
		envFile = ".env"
	}
	if !filepath.IsAbs(envFile) {
		envFile = filepath.Join(repoRoot, envFile)
	}

	host := strings.TrimSpace(os.Getenv("STACKR_HOST"))
	if host == "" {
		host = "0.0.0.0"
	}

	port := strings.TrimSpace(os.Getenv("STACKR_PORT"))
	if port == "" {
		port = "9000"
	}

	stacksDir := strings.TrimSpace(os.Getenv("STACKR_STACKS_DIR"))
	if stacksDir == "" {
		stacksDir = globalCfg.Stacks
	}
	if !filepath.IsAbs(stacksDir) {
		stacksDir = filepath.Join(repoRoot, stacksDir)
	}
	globalCfg.Stacks = stacksDir

	info, err := os.Stat(stacksDir)
	if err != nil {
		return Config{}, fmt.Errorf("failed to stat stacks dir %s: %w", stacksDir, err)
	}
	if !info.IsDir() {
		return Config{}, fmt.Errorf("%s is not a directory", stacksDir)
	}

	return Config{
		Token:     token,
		EnvFile:   envFile,
		Host:      host,
		Port:      port,
		RepoRoot:  repoRoot,
		StacksDir: stacksDir,
		Global:    globalCfg,
	}, nil
}

func (c Config) StackDeployment(stack string) StackConfig {
	deploy := c.Global.Deploy
	meta := deploy[stack]
	tagEnv := strings.TrimSpace(meta.TagEnv)
	if tagEnv == "" {
		tagEnv = defaultTagEnv(stack)
	}

	args := meta.Args
	if len(args) == 0 {
		args = []string{stack, "update"}
	}

	return StackConfig{
		TagEnv: tagEnv,
		Args:   args,
	}
}

func determineRepoRoot() (string, error) {
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		return "", errors.New("unable to determine caller information")
	}

	dir := filepath.Dir(file) // .../stackr/internal/config
	dir = filepath.Dir(dir)   // .../stackr/internal
	dir = filepath.Dir(dir)   // .../stackr
	root := filepath.Dir(dir) // repo root
	return filepath.Abs(root)
}

func loadGlobalConfig(repoRoot string) (GlobalConfig, string, error) {
	path := strings.TrimSpace(os.Getenv("STACKR_CONFIG_FILE"))
	if path == "" {
		path = defaultGlobalConfig
	}
	if !filepath.IsAbs(path) {
		path = filepath.Join(repoRoot, path)
	}

	cfg := defaultGlobal()

	content, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return cfg, path, nil
		}
		return GlobalConfig{}, path, fmt.Errorf("failed to read stackr config %s: %w", path, err)
	}

	if err := yaml.Unmarshal(content, &cfg); err != nil {
		return GlobalConfig{}, path, fmt.Errorf("failed to parse stackr config %s: %w", path, err)
	}

	applyGlobalDefaults(&cfg)

	return cfg, path, nil
}

func defaultGlobal() GlobalConfig {
	return GlobalConfig{
		Stacks: "stacks",
		Cron:   CronConfig{DefaultProfile: "cron"},
		HTTP:   HTTPConfig{BaseDomain: "localhost"},
		Paths: PathsConfig{
			BackupDir: "./backups",
			Pools: map[string]string{
				"SSD": ".vols_ssd/stack_volumes",
				"HDD": ".vols_hdd/stack_volumes",
			},
			Custom: map[string]string{},
		},
		Deploy: map[string]StackDeploy{},
		Env: EnvConfig{
			Global: map[string]string{},
			Stacks: map[string]map[string]string{},
		},
	}
}

func applyGlobalDefaults(cfg *GlobalConfig) {
	if cfg.Stacks == "" {
		cfg.Stacks = "stacks"
	}
	if cfg.Cron.DefaultProfile == "" {
		cfg.Cron.DefaultProfile = "cron"
	}
	if cfg.HTTP.BaseDomain == "" {
		cfg.HTTP.BaseDomain = "localhost"
	}
	if cfg.Paths.BackupDir == "" {
		cfg.Paths.BackupDir = "./backups"
	}
	if cfg.Paths.Pools == nil {
		cfg.Paths.Pools = map[string]string{
			"SSD": ".vols_ssd/stack_volumes",
			"HDD": ".vols_hdd/stack_volumes",
		}
	}
	if cfg.Paths.Custom == nil {
		cfg.Paths.Custom = map[string]string{}
	}

	if cfg.Deploy == nil {
		cfg.Deploy = map[string]StackDeploy{}
	}
	if cfg.Env.Global == nil {
		cfg.Env.Global = map[string]string{}
	}
	if cfg.Env.Stacks == nil {
		cfg.Env.Stacks = map[string]map[string]string{}
	}
}

var tagSanitizer = strings.NewReplacer("-", "_", " ", "_")

func defaultTagEnv(name string) string {
	sanitized := tagSanitizer.Replace(strings.ToUpper(name))
	return sanitized + "_IMAGE_TAG"
}
