// Muxify Extension for OpenCode 2.
//
// Reports this Agent and the Status of the session open in this TUI on its own
// tmux Pane through the pane options @muxify_agent and @muxify_agent_status
// (docs/adr/0004). OpenCode 2 loads it as a TUI plugin from
// ~/.config/opencode/plugins/muxify-status/tui.js.
//
// Every TUI sees the events of every session on the shared OpenCode server, so
// only events from the session tree open here count: the root session and the
// subagent sessions below it (found by walking parentID). The root session's
// executions drive the Status; a permission or form pending anywhere in the
// tree makes it blocked until it is answered.
//
// Known gap: the open session is looked up when an event arrives, so after
// switching to another session in this TUI the Status changes only at that
// session's next event.

import { execFileSync } from "node:child_process";

const AGENT = "opencode";

function setup(api) {
	// Outside tmux there is no Pane to report on.
	const pane = process.env.TMUX_PANE;
	if (!pane) return;

	// Synchronous, so writes land in event order. tmux errors (no server, a
	// closed Pane) are ignored: reporting must never disturb OpenCode.
	function tmux(args) {
		try {
			execFileSync("tmux", args, { stdio: "ignore", timeout: 2000 });
		} catch {}
	}

	const nameAgent = ["set", "-p", "-t", pane, "@muxify_agent", AGENT];

	let disposed = false;
	let owner; // root of the open session when the last counted event arrived
	let lifecycle; // working | done | failed: the owner's last execution
	let blockers = new Set(); // pending "permission:<id>" and "form:<id>"
	let published; // the Status last written; undefined = none yet
	// Parents announced by session.created, in case an event arrives before
	// OpenCode's session cache knows the new (subagent) session.
	const parents = new Map();

	// The root of a session's tree, or undefined for a session nobody knows.
	function root(id) {
		const seen = new Set();
		while (typeof id === "string" && id !== "" && !seen.has(id)) {
			seen.add(id);
			const session = api.data.session.get(id);
			if (!session && !parents.has(id)) return undefined;
			const parentID = session ? session.parentID : parents.get(id);
			if (!parentID) return id;
			id = parentID;
		}
		return undefined;
	}

	function openRoot() {
		const route = api.ui.router.current();
		return route && route.type === "session" ? root(route.sessionID) : undefined;
	}

	// Writes the Status if it changed. Every Status write names the Agent too,
	// in the same tmux call; with no Status known, the Status is unset.
	function publish() {
		const status = blockers.size > 0 ? "blocked" : lifecycle;
		if (status === published) return;
		published = status;
		if (status === undefined) {
			tmux([...nameAgent, ";", "set", "-p", "-u", "-t", pane, "@muxify_agent_status"]);
		} else {
			tmux([...nameAgent, ";", "set", "-p", "-t", pane, "@muxify_agent_status", status]);
		}
	}

	function receive(event) {
		const details = event && event.details;
		const data = details && details.data;
		if (disposed || !data) return;
		const type = details.type;

		if (type === "session.created") {
			if (typeof data.sessionID === "string") parents.set(data.sessionID, data.parentID);
			return;
		}
		if (type === "session.deleted") {
			parents.delete(data.sessionID);
			return;
		}

		const sessionID = type === "form.created" ? data.form && data.form.sessionID : data.sessionID;
		const selected = openRoot();
		if (selected === undefined || root(sessionID) !== selected) return;
		if (selected !== owner) {
			// Another session was opened in this TUI: what we knew belongs to
			// the previous one.
			owner = selected;
			lifecycle = undefined;
			blockers = new Set();
		}

		switch (type) {
			case "session.execution.started":
				if (sessionID !== owner) return; // a subagent's execution
				lifecycle = "working";
				break;
			case "session.execution.succeeded":
			case "session.execution.interrupted": // Esc counts as done
				if (sessionID !== owner) return;
				lifecycle = "done";
				break;
			case "session.execution.failed":
				if (sessionID !== owner) return;
				lifecycle = "failed";
				break;
			case "permission.asked":
				blockers.add(`permission:${data.id}`);
				break;
			case "permission.replied":
				blockers.delete(`permission:${data.requestID}`);
				break;
			case "form.created":
				blockers.add(`form:${data.form.id}`);
				break;
			case "form.replied":
			case "form.cancelled":
				blockers.delete(`form:${data.id}`);
				break;
			default:
				return;
		}
		publish();
	}

	function listener(event) {
		try {
			receive(event);
		} catch {}
	}

	// Cleanup and process exit: unset both options, once.
	function stop() {
		if (disposed) return;
		disposed = true;
		process.removeListener("exit", stop);
		try {
			unsubscribe();
		} catch {}
		tmux([
			"set", "-p", "-u", "-t", pane, "@muxify_agent", ";",
			"set", "-p", "-u", "-t", pane, "@muxify_agent_status",
		]);
	}

	// Name the Agent right away; no Status until the first execution.
	tmux(nameAgent);
	const unsubscribe = api.data.listen(listener);
	process.on("exit", stop);
	return stop;
}

export default { id: "muxify.agent-status", setup };
