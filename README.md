# Symphony

Symphony turns project work into isolated, autonomous implementation runs, allowing teams to manage
work instead of supervising coding agents.

[![Symphony demo video preview](.github/media/symphony-demo-poster.jpg)](.github/media/symphony-demo.mp4)

_In this [demo video](.github/media/symphony-demo.mp4), Symphony monitors a Linear board for work and spawns agents to handle the tasks. The agents complete the tasks and provide proof of work: CI status, PR review feedback, complexity analysis, and walkthrough videos. When accepted, the agents land the PR safely. Engineers do not need to supervise Codex; they can manage the work at a higher level._

> [!WARNING]
> Symphony is a low-key engineering preview for testing in trusted environments.

## Running Symphony

### Requirements

Symphony works best in codebases that have adopted
[harness engineering](https://openai.com/index/harness-engineering/). Symphony is the next step --
moving from managing coding agents to managing work that needs to get done.

### Option 1. Make your own

Tell your favorite coding agent to build Symphony in a programming language of your choice:

> Implement Symphony according to the following spec:
> https://github.com/openai/symphony/blob/main/SPEC.md

### Option 2. Use our experimental reference implementation

Check out [elixir/README.md](elixir/README.md) for instructions on how to set up your environment
and run the Elixir-based Symphony implementation. You can also ask your favorite coding agent to
help with the setup:

> Set up Symphony for my repository based on
> https://github.com/openai/symphony/blob/main/elixir/README.md

> [!NOTE]
> The current GitHub Projects v2 implementation source of truth is
> [PLANS.md](PLANS.md). For v1, keep the same repo-backed issue out of multiple
> configured Symphony projects until duplicate-membership handling is implemented.

> [!NOTE]
> For GitHub Projects v2 setup, configure project workflows intentionally:
> use `Backlog` as the intake state, not `Todo`, because items in `Todo` can be picked up by
> Symphony on the next poll. When GitHub lets you scope `Item added to project`, make it
> `issue`-only so PRs do not hit the intake rule. Disable any built-in workflow that moves
> linked-PR issues to `In Progress`. Keep `Human Review` non-runnable, use `Merging` as the
> approved-by-human handoff state, and let closed issues land in `Done`. If you enable
> `when status changes to Done, close issue`, treat `Done` as a terminal state only and never
> move items there early.

---

## License

This project is licensed under the [Apache License 2.0](LICENSE).
