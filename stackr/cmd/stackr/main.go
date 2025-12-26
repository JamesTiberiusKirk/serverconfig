package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"strings"

	"serverconfig/stackr/internal/config"
	"serverconfig/stackr/internal/stackcmd"
)

const helpMsg = `Stackr CLI - Go replacement for run.sh

Usage:
  stackr [flags] [stacks...]

Examples:
  stackr all update
  stackr mx5parts vars-only -- env | grep STACK_STORAGE
  stackr monitoring get-vars

Flags:
  -h, --help         Show this help message
  -D, --debug        Print debug messages
      --dry-run      Do not execute write actions; print docker compose config

Commands (can be combined):
  all          Run on all stacks
  tear-down    Run "docker compose down" for the stack(s)
  update       Pull latest images and restart stack(s)
  backup       Back up config/volumes to BACKUP_DIR
  vars-only    Load env vars for the stack(s) and execute the command after --
  get-vars     Scan compose files for env vars and append missing entries to .env
`

func main() {
	opts, showHelp, err := parseArgs(os.Args[1:])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}

	if showHelp {
		fmt.Print(helpMsg)
		return
	}

	repoRootOverride := strings.TrimSpace(os.Getenv("STACKR_REPO_ROOT"))
	repoRoot, err := config.ResolveRepoRoot(repoRootOverride)
	if err != nil {
		log.Fatalf("failed to determine repo root: %v", err)
	}

	cfg, err := config.LoadForCLI(repoRoot)
	if err != nil {
		log.Fatalf("failed to load config: %v", err)
	}

	manager, err := stackcmd.NewManager(cfg)
	if err != nil {
		log.Fatalf("failed to initialize stack manager: %v", err)
	}

	if err := manager.Run(context.Background(), opts); err != nil {
		log.Fatalf("error: %v", err)
	}
}

func parseArgs(args []string) (stackcmd.Options, bool, error) {
	var opts stackcmd.Options
	for i := 0; i < len(args); i++ {
		arg := args[i]
		switch arg {
		case "-h", "--help":
			return opts, true, nil
		case "-D", "--debug":
			opts.Debug = true
		case "--dry-run":
			opts.DryRun = true
		case "all":
			opts.All = true
		case "tear-down":
			opts.TearDown = true
		case "update":
			opts.Update = true
		case "backup":
			opts.Backup = true
		case "vars-only":
			opts.VarsOnly = true
		case "get-vars":
			opts.GetVars = true
		case "--":
			opts.VarsOnly = true
			if i+1 < len(args) {
				opts.VarsCommand = append([]string{}, args[i+1:]...)
			}
			i = len(args)
		default:
			if strings.HasPrefix(arg, "-") {
				return opts, false, fmt.Errorf("unknown flag %s", arg)
			}
			if !opts.All {
				opts.Stacks = append(opts.Stacks, arg)
			}
		}
	}

	return opts, false, nil
}
