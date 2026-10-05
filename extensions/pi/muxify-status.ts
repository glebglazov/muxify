// Muxify Extension for Pi.
//
// Reports this Agent and the Status of its runs on its own tmux Pane through
// the pane options @muxify_agent and @muxify_agent_status (docs/adr/0004).
// Pi loads it from ~/.pi/agent/extensions/muxify-status.ts.
//
// Only the interactive TUI reports: Pi children spawned in json or print mode
// (subagents, scripts) inherit TMUX_PANE and must not touch the Pane.
//
// A run is working from agent_start until agent_settled, which ends it as
// failed when its last assistant message stopped with an error, otherwise as
// done (Esc aborts count as done). While any dialog is open (ui_prompt_start
// to ui_prompt_end, Pi >= 0.84.4) the Status is blocked. Quitting Pi unsets
// both options.
//
// Plain TypeScript that Node runs by stripping types: no enums, namespaces or
// parameter properties.

import { execFileSync } from "node:child_process";
import type {
	AgentEndEvent,
	ExtensionAPI,
	ExtensionContext,
	SessionShutdownEvent,
} from "@earendil-works/pi-coding-agent";

type Status = "working" | "blocked" | "done" | "failed";

const AGENT = "pi";

export default function (pi: ExtensionAPI) {
	// Outside tmux there is no Pane to report on.
	const pane = process.env.TMUX_PANE || "";
	if (pane === "") return;

	// Synchronous, so writes land in event order. tmux errors (no server, a
	// closed Pane) are ignored: reporting must never disturb Pi.
	function tmux(args: string[]) {
		try {
			execFileSync("tmux", args, { stdio: "ignore", timeout: 2000 });
		} catch {}
	}

	const nameAgent = ["set", "-p", "-t", pane, "@muxify_agent", AGENT];

	let lifecycle: Status | undefined; // working | done | failed: the last run's
	let dialog = false; // a dialog is open
	let stopReason: string | undefined; // the last run's last assistant message's
	let published: Status | undefined; // the Status last written; undefined = none yet
	let quit = false;

	// Writes the Status if it changed. Every Status write names the Agent too,
	// in the same tmux call; with no Status known, the Status is unset.
	function publish() {
		const status = dialog ? "blocked" : lifecycle;
		if (status === published) return;
		published = status;
		if (status === undefined) {
			tmux([...nameAgent, ";", "set", "-p", "-u", "-t", pane, "@muxify_agent_status"]);
		} else {
			tmux([...nameAgent, ";", "set", "-p", "-t", pane, "@muxify_agent_status", status]);
		}
	}

	// Wraps a handler so it runs only in the TUI, never after quit, and never
	// throws into Pi.
	function guard<E>(handler: (e: E, ctx: ExtensionContext) => void) {
		return (e: E, ctx: ExtensionContext) => {
			try {
				if (quit || !ctx || ctx.mode !== "tui") return;
				handler(e, ctx);
			} catch {}
		};
	}

	// Name the Agent; no Status until the first run.
	pi.on("session_start", guard(() => {
		tmux(nameAgent);
	}));

	pi.on("agent_start", guard(() => {
		stopReason = undefined;
		lifecycle = "working";
		publish();
	}));

	pi.on("ui_prompt_start", guard(() => {
		dialog = true;
		publish();
	}));

	pi.on("ui_prompt_end", guard(() => {
		dialog = false;
		publish();
	}));

	pi.on("agent_end", guard((e: AgentEndEvent) => {
		const messages = Array.isArray(e && e.messages) ? e.messages : [];
		const last = messages.findLast((m) => m && m.role === "assistant");
		stopReason = last && "stopReason" in last ? last.stopReason : undefined;
	}));

	// Fires once the run is over, after any retry, compaction or queued
	// continuation; a run still going (not idle) keeps its Status.
	pi.on("agent_settled", guard((_e, ctx) => {
		if (!ctx.isIdle()) return;
		lifecycle = stopReason === "error" ? "failed" : "done"; // "aborted" (Esc) is done
		publish();
	}));

	// Reload, new, resume and fork tear this runtime down too, but Pi keeps
	// running and the next runtime takes over; only quitting unsets.
	pi.on("session_shutdown", guard((e: SessionShutdownEvent) => {
		if (!e || e.reason !== "quit") return;
		quit = true;
		tmux([
			"set", "-p", "-u", "-t", pane, "@muxify_agent", ";",
			"set", "-p", "-u", "-t", pane, "@muxify_agent_status",
		]);
	}));
}
