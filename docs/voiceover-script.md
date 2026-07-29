# ASH Demo — Voiceover Script

Target: ~2 minutes. Keep scrolling steady — let the visuals do the work.

---

## Header Stats (~10s)

> "This is CockroachDB's Active Session History. These four stats give you an instant health check — average active sessions, how many apps are running, and the percentage of time in lock contention and admission throttling."

## Overview: Stacked Area + Donut (~15s)

> "The main chart shows every active session sampled once per second, stacked by resource type — CPU, IO, Lock, Network, Admission. The donut on the right shows the current mix. In a healthy cluster, CPU and IO dominate."

## Work Event Type Detail: CPU / IO / Network Breakdowns (~15s)

> "Drilling into each work event type — you can see the specific sub-events consuming CPU, IO, and Network, split by user SQL, jobs, and system work. The filtered panel below responds to the dropdown for quick drill-downs."

## Workload Types & Applications (~15s)

> "User SQL, background jobs, and system work are separated cleanly. The bar chart on the right shows which application is consuming the most resources — no guessing which app is the problem."

## Node & Lock Analysis (~20s)

> "Per-node view shows when and where hotspots occur. The lock contention table surfaces which apps and SQL statements are generating lock waits. The heatmap reveals which app is hammering which node."

## Top SQL (~15s)

> "Top SQL statements by ASH samples — with the actual query text, application name, and a CPU/IO/Lock/Network breakdown. Click any row to drill into the statement detail dashboard."

## Background Work (~15s)

> "Admission control, system internals, and job analysis — all in one row. If your OLTP latency spiked during a backup, this is where you prove it."

## Closing (~5s)

> "All from one cluster setting — no agents, no exporters. Just SQL."
