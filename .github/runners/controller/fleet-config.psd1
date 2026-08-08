# Fleet policy constants. This file is the single source of truth for the numbers that
# used to live in runner-reconcile.yml's env: block, and tests/runner-policy.Tests.ps1
# asserts the janitor stays aligned with it.
#
# Every key can be overridden by an app setting of the same name on the Function App,
# which is the emergency lever: change one number in the portal, no redeploy. The
# committed values here are what the fleet runs on normally.
@{
    # Hard VMSS ceiling. Get-DesiredRunnerPools throws rather than exceed it.
    MAX_RUNNERS             = 35

    # Shared lane for everyone who is not a maintainer.
    COMMUNITY_COUNT         = 5
    COMMUNITY_GRACE_MINUTES = 20

    # Each maintainer gets an independent lane.
    BOOST_USERS             = "potatoqualitee andreasjordan niphlod"
    BOOST_COUNT             = 10
    BOOST_HOURS             = 1

    # Held by a lane that is hot but has nothing pending. Mirrored by $warmFloor in
    # janitor-runbook.ps1.
    WARM_FLOOR              = 3

    # Users whose pushes do NOT heat a lane unless the head commit carries CI_MARKER.
    OPT_IN_PUSH_USERS       = "potatoqualitee"
    CI_MARKER               = "[do ci]"

    # Base runner label. Pool labels are dbatools-pool-<lane> on top of it.
    RUNNER_LABEL            = "dbatools-modern"
    POOL_LABEL_PREFIX       = "dbatools-pool-"

    # Workflow the controller reads demand from and dispatches marked pushes to.
    CI_WORKFLOW             = "ci-azure.yml"

    # A queued nudge older than this is dropped unprocessed. Every pass re-reads all
    # of GitHub and Azure anyway, so a stale wake-up adds nothing -- and when a run
    # burst backs the queue up (2026-08-08: 3.3 hours behind), replaying old nudges
    # one serialized pass at a time is exactly what keeps it behind. The safety tick
    # enqueues a fresh nudge every five minutes, so dropping never strands the fleet.
    # Zero disables the drop.
    STALE_NUDGE_MINUTES     = 5
}
