BeforeAll {
    $script:ControllerRoot = (Resolve-Path "$PSScriptRoot/../controller").Path
    Import-Module "$script:ControllerRoot/Modules/GitHubAppAuth/GitHubAppAuth.psm1" -Force
    Import-Module "$script:ControllerRoot/Modules/FleetCore/FleetCore.psm1" -Force

    function ConvertFrom-Base64Url {
        param([string]$Text)
        $padded = $Text.Replace("-", "+").Replace("_", "/")
        switch ($padded.Length % 4) {
            2 { $padded = "$padded==" }
            3 { $padded = "$padded=" }
        }
        [Convert]::FromBase64String($padded)
    }

    function Get-TestSignature {
        param([string]$Body, [string]$Secret)
        $hmac = New-Object -TypeName System.Security.Cryptography.HMACSHA256
        try {
            $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($Secret)
            $hash = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Body))
        } finally {
            $hmac.Dispose()
        }
        "sha256=" + (($hash | ForEach-Object { $PSItem.ToString("x2") }) -join "")
    }
}

AfterAll {
    Remove-Module -Name FleetCore, GitHubAppAuth -Force -ErrorAction SilentlyContinue
}

Describe "fleet configuration" {
    It "reads the committed policy constants" {
        $config = Get-FleetConfig
        $config["MAX_RUNNERS"] | Should -Be 35
        $config["WARM_FLOOR"] | Should -Be 3
        $config["RUNNER_LABEL"] | Should -Be "dbatools-modern"
        $config["CI_MARKER"] | Should -Be "[do ci]"
        $config["STALE_NUDGE_MINUTES"] | Should -Be 5
    }

    It "lets an app setting override a committed constant" {
        $env:WARM_FLOOR = "7"
        try {
            (Get-FleetConfig)["WARM_FLOOR"] | Should -Be "7"
        } finally {
            Remove-Item -Path env:WARM_FLOOR
        }
    }
}

Describe "GitHub App authentication" {
    BeforeAll {
        $script:Rsa = [System.Security.Cryptography.RSA]::Create(2048)
        $script:Pem = $script:Rsa.ExportRSAPrivateKeyPem()
    }

    AfterAll {
        $script:Rsa.Dispose()
    }

    It "signs a JWT GitHub will accept" {
        $jwt = New-GitHubAppJwt -AppId "1234567" -PrivateKeyPem $script:Pem
        $parts = $jwt -split "\."
        $parts.Count | Should -Be 3

        $header = [System.Text.Encoding]::UTF8.GetString((ConvertFrom-Base64Url -Text $parts[0])) | ConvertFrom-Json
        $header.alg | Should -Be "RS256"
        $header.typ | Should -Be "JWT"

        $claims = [System.Text.Encoding]::UTF8.GetString((ConvertFrom-Base64Url -Text $parts[1])) | ConvertFrom-Json
        $claims.iss | Should -Be "1234567"
        # Backdated one minute, ten-minute ceiling: GitHub rejects anything outside that.
        ($claims.exp - $claims.iat) | Should -Be 600
        $claims.iat | Should -BeLessThan ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())

        $splatVerify = @{
            Data          = [System.Text.Encoding]::UTF8.GetBytes("$($parts[0]).$($parts[1])")
            Signature     = (ConvertFrom-Base64Url -Text $parts[2])
            HashAlgorithm = [System.Security.Cryptography.HashAlgorithmName]::SHA256
            Padding       = [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
        }
        $verified = $script:Rsa.VerifyData($splatVerify.Data, $splatVerify.Signature, $splatVerify.HashAlgorithm, $splatVerify.Padding)
        $verified | Should -BeTrue
    }

    It "accepts a PEM whose newlines arrived escaped from an app setting" {
        $escaped = $script:Pem.Replace("`n", "\n")
        { New-GitHubAppJwt -AppId "1234567" -PrivateKeyPem $escaped } | Should -Not -Throw
    }
}

Describe "webhook signature validation" {
    BeforeAll {
        $script:Body = "{`"action`":`"queued`",`"number`":7}"
        $script:Secret = "not-the-real-webhook-secret"
        $script:Good = Get-TestSignature -Body $script:Body -Secret $script:Secret
    }

    It "accepts a delivery signed with the shared secret" {
        $splatValid = @{
            Body      = $script:Body
            Signature = $script:Good
            Secret    = $script:Secret
        }
        Test-GitHubWebhookSignature @splatValid | Should -BeTrue
    }

    It "rejects a body that changed after signing" {
        $splatTampered = @{
            Body      = $script:Body.Replace("7", "8")
            Signature = $script:Good
            Secret    = $script:Secret
        }
        Test-GitHubWebhookSignature @splatTampered | Should -BeFalse
    }

    It "rejects a signature made with a different secret" {
        $splatWrongSecret = @{
            Body      = $script:Body
            Signature = (Get-TestSignature -Body $script:Body -Secret "some-other-secret")
            Secret    = $script:Secret
        }
        Test-GitHubWebhookSignature @splatWrongSecret | Should -BeFalse
    }

    It "rejects a delivery with no signature at all" {
        $splatMissing = @{
            Body      = $script:Body
            Signature = ""
            Secret    = $script:Secret
        }
        Test-GitHubWebhookSignature @splatMissing | Should -BeFalse
    }

    It "rejects the retired sha1 signature header format" {
        $splatSha1 = @{
            Body      = $script:Body
            Signature = "sha1=0123456789abcdef0123456789abcdef01234567"
            Secret    = $script:Secret
        }
        Test-GitHubWebhookSignature @splatSha1 | Should -BeFalse
    }
}

Describe "webhook event filtering" {
    BeforeAll {
        $script:BoostUsers = @("potatoqualitee", "andreasjordan", "niphlod")
    }

    BeforeEach {
        $script:SplatNudge = @{
            BoostUsers  = $script:BoostUsers
            RunnerLabel = "dbatools-modern"
            CiWorkflow  = "ci-azure.yml"
        }
    }

    It "wakes a pass when a fleet job is queued" {
        $splatJob = $script:SplatNudge + @{
            EventName = "workflow_job"
            Payload   = [pscustomobject]@{
                action       = "queued"
                workflow_job = [pscustomobject]@{
                    labels = @("self-hosted", "dbatools-modern", "dbatools-pool-niphlod")
                }
            }
        }
        (Get-FleetNudge @splatJob).reason | Should -Be "workflow_job.queued"
    }

    It "ignores the ubuntu-latest authorize job in ci-azure" {
        $splatAuthorize = $script:SplatNudge + @{
            EventName = "workflow_job"
            Payload   = [pscustomobject]@{
                action       = "queued"
                workflow_job = [pscustomobject]@{ labels = @("ubuntu-latest") }
            }
        }
        Get-FleetNudge @splatAuthorize | Should -BeNullOrEmpty
    }

    It "ignores a job that merely started running" {
        $splatInProgress = $script:SplatNudge + @{
            EventName = "workflow_job"
            Payload   = [pscustomobject]@{
                action       = "in_progress"
                workflow_job = [pscustomobject]@{ labels = @("dbatools-modern") }
            }
        }
        Get-FleetNudge @splatInProgress | Should -BeNullOrEmpty
    }

    It "ignores a workflow_run for a workflow the fleet does not serve" {
        $splatOtherWorkflow = $script:SplatNudge + @{
            EventName = "workflow_run"
            Payload   = [pscustomobject]@{
                action       = "requested"
                workflow_run = [pscustomobject]@{ path = ".github/workflows/gallery.yml" }
            }
        }
        Get-FleetNudge @splatOtherWorkflow | Should -BeNullOrEmpty
    }

    It "wakes a pass when a CI run is requested" {
        $splatCiRun = $script:SplatNudge + @{
            EventName = "workflow_run"
            Payload   = [pscustomobject]@{
                action       = "requested"
                workflow_run = [pscustomobject]@{ path = ".github/workflows/ci-azure.yml" }
            }
        }
        (Get-FleetNudge @splatCiRun).reason | Should -Be "workflow_run.requested"
    }

    It "carries the head commit through on a maintainer push" {
        $splatPush = $script:SplatNudge + @{
            EventName = "push"
            Payload   = [pscustomobject]@{
                sender      = [pscustomobject]@{ login = "niphlod" }
                after       = "abc1234"
                ref         = "refs/heads/development"
                head_commit = [pscustomobject]@{ message = "Fix a thing [do ci]" }
            }
        }
        $nudge = Get-FleetNudge @splatPush
        $nudge.reason | Should -Be "push"
        $nudge.actor | Should -Be "niphlod"
        $nudge.sha | Should -Be "abc1234"
        $nudge.ref | Should -Be "refs/heads/development"
        $nudge.message | Should -Be "Fix a thing [do ci]"
    }

    It "ignores a branch deletion, which arrives as a push naming the null sha" {
        $splatDeletedPush = $script:SplatNudge + @{
            EventName = "push"
            Payload   = [pscustomobject]@{
                sender      = [pscustomobject]@{ login = "potatoqualitee" }
                deleted     = $true
                after       = "0000000000000000000000000000000000000000"
                ref         = "refs/heads/squash-merged-branch"
                head_commit = $null
            }
        }
        Get-FleetNudge @splatDeletedPush | Should -BeNullOrEmpty
    }

    It "ignores a push from someone with no lane" {
        $splatStrangerPush = $script:SplatNudge + @{
            EventName = "push"
            Payload   = [pscustomobject]@{
                sender      = [pscustomobject]@{ login = "a-first-time-contributor" }
                after       = "def5678"
                ref         = "refs/heads/development"
                head_commit = [pscustomobject]@{ message = "Fix a thing [do ci]" }
            }
        }
        Get-FleetNudge @splatStrangerPush | Should -BeNullOrEmpty
    }

    It "ignores event types the controller has no use for" {
        $splatIssue = $script:SplatNudge + @{
            EventName = "issues"
            Payload   = [pscustomobject]@{ action = "opened" }
        }
        Get-FleetNudge @splatIssue | Should -BeNullOrEmpty
    }
}

Describe "trigger corroboration" {
    BeforeAll {
        InModuleScope FleetCore {
            $script:Fleet = [pscustomobject]@{ Repo = "dataplat/dbatools" }
        }
    }

    It "drops a hint whose sha is no longer the head of the ref" {
        InModuleScope FleetCore {
            Mock Invoke-GhJson {
                [pscustomobject]@{
                    sha    = "1111111111111111111111111111111111111111"
                    commit = [pscustomobject]@{ message = "Newer work [do ci]" }
                    author = [pscustomobject]@{ login = "potatoqualitee" }
                }
            }
            $splatStale = @{
                Actor = "potatoqualitee"
                Sha   = "2222222222222222222222222222222222222222"
                Ref   = "refs/heads/development"
            }
            $trigger = Confirm-DirectTrigger @splatStale
            $trigger.Sha | Should -BeNullOrEmpty
            $trigger.Actor | Should -BeNullOrEmpty
        }
    }

    It "takes the marker message from GitHub rather than from the caller" {
        InModuleScope FleetCore {
            Mock Invoke-GhJson {
                [pscustomobject]@{
                    sha    = "3333333333333333333333333333333333333333"
                    commit = [pscustomobject]@{ message = "Real message, no marker" }
                    author = [pscustomobject]@{ login = "potatoqualitee" }
                }
            }
            $splatCurrent = @{
                Actor = "potatoqualitee"
                Sha   = "3333333333333333333333333333333333333333"
                Ref   = "refs/heads/development"
            }
            $trigger = Confirm-DirectTrigger @splatCurrent
            $trigger.Sha | Should -Be "3333333333333333333333333333333333333333"
            $trigger.Message | Should -Be "Real message, no marker"
        }
    }

    It "never calls GitHub for an empty or non-branch hint" {
        InModuleScope FleetCore {
            Mock Invoke-GhJson { throw "GitHub should not have been called" }
            (Confirm-DirectTrigger -Actor "" -Sha "" -Ref "").Sha | Should -BeNullOrEmpty
            $splatOdd = @{
                Actor = "potatoqualitee"
                Sha   = "4444444444444444444444444444444444444444"
                Ref   = "refs/heads/../../etc"
            }
            (Confirm-DirectTrigger @splatOdd).Sha | Should -BeNullOrEmpty
            Should -Invoke Invoke-GhJson -Times 0
        }
    }

    It "ignores a tag push, because a release tag is not a lane" {
        # The push webhook fires for tags as well as branches, and refs/tags/v2.1.0 survives
        # the branch-name check, resolves at the commits endpoint and dispatches. So without
        # a branch test, cutting a release heated a pool and ran CI at the tag.
        InModuleScope FleetCore {
            Mock Invoke-GhJson { throw "GitHub should not have been called" }
            $splatTag = @{
                Actor = "potatoqualitee"
                Sha   = "6666666666666666666666666666666666666666"
                Ref   = "refs/tags/v2.1.0"
            }
            $tagTrigger = Confirm-DirectTrigger @splatTag
            $tagTrigger.Sha | Should -BeNullOrEmpty
            $tagTrigger.Actor | Should -BeNullOrEmpty
            Should -Invoke Invoke-GhJson -Times 0
        }
    }

    It "never calls GitHub for the null-object sha a branch deletion names" {
        InModuleScope FleetCore {
            Mock Invoke-GhJson { throw "GitHub should not have been called" }
            $splatDeleted = @{
                Actor = "potatoqualitee"
                Sha   = "0000000000000000000000000000000000000000"
                Ref   = "refs/heads/squash-merged-branch"
            }
            $deletedTrigger = Confirm-DirectTrigger @splatDeleted
            $deletedTrigger.Sha | Should -BeNullOrEmpty
            $deletedTrigger.Actor | Should -BeNullOrEmpty
            Should -Invoke Invoke-GhJson -Times 0
        }
    }

    It "attributes the trigger to the pusher, not to whoever wrote the commit" {
        # The maintainer and opt-in lists are about who pushed. Reading the lane from
        # head.author.login would hand a maintainer lane to anyone who pushes a commit a
        # maintainer wrote, and deny one to a maintainer pushing a contributor's work.
        InModuleScope FleetCore {
            Mock Invoke-GhJson {
                [pscustomobject]@{
                    sha    = "5555555555555555555555555555555555555555"
                    commit = [pscustomobject]@{ message = "Contributed work [do ci]" }
                    author = [pscustomobject]@{ login = "potatoqualitee" }
                }
            }
            $splatMismatch = @{
                Actor = "some-drive-by"
                Sha   = "5555555555555555555555555555555555555555"
                Ref   = "refs/heads/development"
            }
            $trigger = Confirm-DirectTrigger @splatMismatch
            $trigger.Actor | Should -Be "some-drive-by"
        }
    }
}

Describe "stale nudge dropping" {
    BeforeAll {
        $script:ReconcileScript = Join-Path -Path $script:ControllerRoot -ChildPath "ReconcileQueue/run.ps1"
    }

    BeforeEach {
        Mock Get-FleetConfig { @{ STALE_NUDGE_MINUTES = 5 } }
        Mock Invoke-FleetReconcile { }
        $script:NudgeJson = "{`"reason`":`"safety-tick`",`"delivery`":`"test-delivery`"}"
    }

    It "reconciles a nudge that is younger than the stale window" {
        $freshMetadata = @{
            InsertionTime = [DateTimeOffset]::UtcNow.AddMinutes(-1)
            DequeueCount  = 1
        }
        & $script:ReconcileScript -QueueItem $script:NudgeJson -TriggerMetadata $freshMetadata
        Should -Invoke Invoke-FleetReconcile -Times 1 -Exactly
    }

    It "drops a nudge that sat in the queue past the stale window" {
        # String-typed timestamp on purpose: the worker may hand InsertionTime over as
        # either a DateTimeOffset or its serialized form, and both routes must age.
        $staleMetadata = @{
            InsertionTime = ([DateTimeOffset]::UtcNow.AddMinutes(-10)).ToString("o")
            DequeueCount  = 1
        }
        & $script:ReconcileScript -QueueItem $script:NudgeJson -TriggerMetadata $staleMetadata
        Should -Invoke Invoke-FleetReconcile -Times 0 -Exactly
    }

    It "treats a missing insertion time as fresh, not as infinitely old" {
        $bareMetadata = @{ DequeueCount = 1 }
        & $script:ReconcileScript -QueueItem $script:NudgeJson -TriggerMetadata $bareMetadata 3>$null
        Should -Invoke Invoke-FleetReconcile -Times 1 -Exactly
    }

    It "treats an unreadable insertion time as fresh" {
        $garbledMetadata = @{
            InsertionTime = "not-a-timestamp"
            DequeueCount  = 1
        }
        & $script:ReconcileScript -QueueItem $script:NudgeJson -TriggerMetadata $garbledMetadata 3>$null
        Should -Invoke Invoke-FleetReconcile -Times 1 -Exactly
    }
}

Describe "registration readiness" {
    It "does not send a RunCommand to a VM that is still provisioning" {
        # Scale-out no longer waits for readiness in-pass, so Register-PoolVms now sees
        # instances mid-build. A RunCommand against one of those fails; the VM keeps its
        # pool tag and registers on a later pass instead.
        InModuleScope FleetCore {
            $script:Fleet = [pscustomobject]@{
                DryRun          = $false
                Repo            = "dataplat/dbatools"
                RunnerLabel     = "dbatools-modern"
                PoolLabelPrefix = "dbatools-pool-"
            }
            Mock Invoke-GhJson { throw "no registration token should have been minted" }
            $creatingState = [pscustomobject]@{
                Vms     = @(
                    [pscustomobject]@{
                        name         = "runner-000042"
                        id           = "/subscriptions/s/resourceGroups/rg/providers/Microsoft.Compute/virtualMachines/runner-000042"
                        provisioning = "Creating"
                        tags         = [pscustomobject]@{ runnerPool = "potatoqualitee" }
                    }
                )
                Runners = @()
            }
            Register-PoolVms -State $creatingState -Desired @{ potatoqualitee = 1 }
            Should -Invoke Invoke-GhJson -Times 0
        }
    }
}

Describe "capacity step ordering" {
    BeforeEach {
        InModuleScope FleetCore {
            $script:Fleet = [pscustomobject]@{
                DryRun         = $false
                SubscriptionId = "sub"
                ResourceGroup  = "rg"
                Vmss           = "dbatools-runners"
                MaxRunners     = 35
            }
        }
        # These flags parameterize the mock bodies below, which execute in this test
        # file's scope even though the mocks intercept calls inside FleetCore -- only
        # $script:Fleet above has to live in the module, because the real reconcile
        # code reads it there.
        $script:CapacityReadSeen = $false
        $script:CapacityReadMalformed = $false
        $script:FleetStateGarbled = $false
        $script:FleetListsVms = $true
        $script:FleetRepopulatesOnConfirm = $false
        $script:PostReadStateCalls = 0
        $script:FleetOnlineRunners = @()
        $script:CapacityStepValue = $null
        Mock -ModuleName FleetCore Initialize-FleetContext { }
        Mock -ModuleName FleetCore Get-RunnerDemand {
            @{
                Dispatch = $null
                Desired  = @{}
            }
        }
        Mock -ModuleName FleetCore Get-OrphanedNetworking { $null }
        Mock -ModuleName FleetCore Get-FleetState {
            if ($script:FleetStateGarbled) {
                return [pscustomobject]@{
                    Vms     = $null
                    Runners = $null
                }
            }
            $vms = @()
            if ($script:CapacityReadSeen) {
                $script:PostReadStateCalls++
                if ($script:FleetListsVms) {
                    $vms = @(foreach ($vmSuffix in "a", "b", "c") {
                            [pscustomobject]@{
                                name         = "dbatools-runners_$vmSuffix"
                                provisioning = "Succeeded"
                                tags         = $null
                            }
                        })
                } elseif ($script:FleetRepopulatesOnConfirm -and $script:PostReadStateCalls -ge 2) {
                    $vms = @(
                        [pscustomobject]@{
                            name         = "dbatools-runners_late"
                            provisioning = "Succeeded"
                            tags         = $null
                        }
                    )
                }
            }
            [pscustomobject]@{
                Vms     = $vms
                Runners = $script:FleetOnlineRunners
            }
        }
        Mock -ModuleName FleetCore Invoke-ArmJson {
            $script:CapacityReadSeen = $true
            if ($script:CapacityReadMalformed) {
                return [pscustomobject]@{
                    properties = [pscustomobject]@{ provisioningState = "Succeeded" }
                }
            }
            [pscustomobject]@{
                sku        = [pscustomobject]@{ capacity = 9 }
                properties = [pscustomobject]@{ provisioningState = "Succeeded" }
            }
        }
        Mock -ModuleName FleetCore Get-FleetCapacityStep { $script:CapacityStepValue }
        Mock -ModuleName FleetCore Invoke-ArmWeb { }
        Mock -ModuleName FleetCore Set-UnallocatedVmPool { }
        Mock -ModuleName FleetCore Register-PoolVms { }
        Mock -ModuleName FleetCore Set-VmOnlineObservedAt { }
        Mock -ModuleName FleetCore Remove-OrphanedNetworking { }
        Mock -ModuleName FleetCore Set-FleetHeartbeat { }
    }

    It "prices the capacity step from an inventory listed after the settled-state read" {
        # A list taken before the provisioning-state read can predate a just-completed
        # scale-out, and a stale-low count would send a capacity PATCH below the real
        # membership. The fleet here is empty until the capacity read happens and
        # holds three VMs afterwards: only the read-then-list order sees all three.
        Invoke-FleetReconcile

        $freshInventoryFilter = {
            $ProvisioningState -eq "Succeeded" -and
            $NominalCapacity -eq 9 -and
            $ActualCapacity -eq 3 -and
            $TargetCapacity -eq 0
        }
        Should -Invoke Get-FleetCapacityStep -ModuleName FleetCore -Times 1 -Exactly -ParameterFilter $freshInventoryFilter
    }

    It "bails out of the pass when the capacity read comes back without a sku" {
        # [int]$null coerces to 0, and a falsely-zero nominal turns the compensated
        # scale-out into a down-PATCH from Azure's real figure. The pass has to end
        # before a step is priced from a guessed number.
        $script:CapacityReadMalformed = $true

        Invoke-FleetReconcile 3>$null

        Should -Invoke Get-FleetCapacityStep -ModuleName FleetCore -Times 0 -Exactly
        Should -Invoke Invoke-ArmWeb -ModuleName FleetCore -Times 0 -Exactly
        Should -Invoke Set-FleetHeartbeat -ModuleName FleetCore -Times 0 -Exactly
    }

    It "bails out of the pass when the inventory read comes back null" {
        # A null Vms list is a garbled read, not an empty fleet -- @($null).Count is 1,
        # so unguarded it would impersonate a single live VM -- and a null runner list
        # would slide through the reclaim corroboration as zero online. Neither may
        # price a step.
        $script:FleetStateGarbled = $true

        Invoke-FleetReconcile 3>$null

        Should -Invoke Get-FleetCapacityStep -ModuleName FleetCore -Times 0 -Exactly
        Should -Invoke Invoke-ArmWeb -ModuleName FleetCore -Times 0 -Exactly
        Should -Invoke Set-FleetHeartbeat -ModuleName FleetCore -Times 0 -Exactly
    }

    It "refuses the zero reclaim while GitHub still shows an online runner" {
        # The reclaim is computed from the ARM VM list, and GitHub is an independent
        # witness against it: a runner cannot be online without a live VM behind it,
        # so an online count contradicting an empty list means the list is stale and
        # the PATCH would delete the instances the list failed to return.
        $script:FleetListsVms = $false
        $script:CapacityStepValue = 0
        $script:FleetOnlineRunners = @(
            [pscustomobject]@{
                name   = "dbatools-runners_a"
                status = "online"
                busy   = $false
            }
        )

        Invoke-FleetReconcile 3>$null

        Should -Invoke Invoke-ArmWeb -ModuleName FleetCore -Times 0 -Exactly
    }

    It "refuses the zero reclaim when the confirming re-read finds the fleet repopulated" {
        # The first read came back empty and priced the step at zero; the confirming
        # read sees a VM that the first one missed. One witness recanting is enough
        # to hold fire for a pass.
        $script:FleetListsVms = $false
        $script:CapacityStepValue = 0
        $script:FleetRepopulatesOnConfirm = $true

        Invoke-FleetReconcile 3>$null

        Should -Invoke Invoke-ArmWeb -ModuleName FleetCore -Times 0 -Exactly
    }

    It "reclaims to zero once GitHub agrees the fleet is empty" {
        $script:FleetListsVms = $false
        $script:CapacityStepValue = 0

        Invoke-FleetReconcile

        Should -Invoke Invoke-ArmWeb -ModuleName FleetCore -Times 1 -Exactly -ParameterFilter { $Body.sku.capacity -eq 0 }
    }
}

Describe "fail-closed settings" {
    BeforeAll {
        # Everything Initialize-FleetContext demands before it looks at DRY_RUN, so the
        # required-settings check is not what fires
        $script:RequiredForInit = @{
            REPO                   = "dataplat/dbatools"
            RG                     = "dbatools-ci"
            VMSS                   = "dbatools-runners"
            SUBSCRIPTION_ID        = "00000000-0000-0000-0000-000000000000"
            GITHUB_APP_ID          = "1234567"
            GITHUB_INSTALLATION_ID = "7654321"
            GITHUB_APP_PRIVATE_KEY = "not-a-real-key"
        }
        $script:SavedForInit = @{ }
        foreach ($settingName in $script:RequiredForInit.Keys) {
            $script:SavedForInit[$settingName] = [Environment]::GetEnvironmentVariable($settingName)
            [Environment]::SetEnvironmentVariable($settingName, $script:RequiredForInit[$settingName])
        }
        $script:SavedDryRun = $env:DRY_RUN
    }

    AfterAll {
        foreach ($settingName in $script:SavedForInit.Keys) {
            [Environment]::SetEnvironmentVariable($settingName, $script:SavedForInit[$settingName])
        }
        $env:DRY_RUN = $script:SavedDryRun
    }

    It "refuses to start unless DRY_RUN says exactly true or false" {
        # A DRY_RUN that does not parse used to read as "not dry", which arms a controller
        # that was only meant to be shadowing. The setting is one typo away from that.
        foreach ($badValue in @($null, "", "yes", "0", "TRUE ")) {
            $env:DRY_RUN = $badValue
            $splatRefused = @{
                ExpectedMessage = "*DRY_RUN*"
                Because         = "`"$badValue`" is not a value the controller may guess at"
            }
            { InModuleScope FleetCore { Initialize-FleetContext } } | Should -Throw @splatRefused
        }
    }

    It "accepts the two words it does understand" {
        foreach ($goodValue in @("true", "false", "TRUE")) {
            $env:DRY_RUN = $goodValue
            $context = InModuleScope FleetCore { Initialize-FleetContext }
            $context.DryRun | Should -Be ($goodValue -eq "true" -or $goodValue -eq "TRUE")
        }
    }
}

Describe "Azure inventory paging" {
    It "follows nextLink so no fleet VM is invisible" {
        InModuleScope FleetCore {
            $script:PagingCalls = 0
            Mock Invoke-ArmJson {
                $script:PagingCalls++
                if ($script:PagingCalls -eq 1) {
                    return [pscustomobject]@{
                        value    = @([pscustomobject]@{ name = "page-one" })
                        nextLink = "https://management.azure.com/next"
                    }
                }
                [pscustomobject]@{ value = @([pscustomobject]@{ name = "page-two" }) }
            }
            $found = @(Invoke-ArmList -Path "/subscriptions/x/vms" -Operation "test paging")
            $found.Count | Should -Be 2
            $found.name | Should -Contain "page-two"
        }
    }

    It "pages every ARM list, so orphaned NICs and IPs past a page boundary still get reaped" {
        # az followed nextLink for us and raw REST does not, so a list call that skipped the
        # helper would leave the tail of the inventory both uncounted and unreaped
        $source = Get-Content -Path "$script:ControllerRoot/Modules/FleetCore/FleetCore.psm1" -Raw
        $listPaths = [regex]::Matches($source, "(?m)^\s*Path\s*=\s*`"[^`"]*providers/Microsoft\.(Compute|Network)/[a-zA-Z]+\?api-version[^`"]*`"")
        $listPaths.Count | Should -BeGreaterThan 0
        foreach ($listPath in $listPaths) {
            $tail = $source.Substring($listPath.Index, [math]::Min(400, $source.Length - $listPath.Index))
            $tail | Should -Match "Invoke-ArmList" -Because "the list at $($listPath.Value.Trim()) has to paginate"
        }
    }
}

Describe "controller-infra rerun safety" {
    BeforeAll {
        # The decision is executed rather than described: the region is lifted verbatim out of
        # the shipped script and dot-sourced against a stubbed az, so the test breaks if the
        # script changes. It is anchored on the last committed app setting and on the tick
        # itself, both of which are load-bearing lines nobody edits by accident.
        $infraSource = Get-Content -Path "$PSScriptRoot/../controller-infra.ps1" -Raw
        $splatRegion = @{
            Input   = $infraSource
            Pattern = "(?s)PSWorkerInProcConcurrencyUpperBound=10`"\r?\n\)\r?\n(.*?SafetyTick\.Disabled=0`"\r?\n\})"
        }
        $regionMatch = [regex]::Match($splatRegion.Input, $splatRegion.Pattern)
        $regionMatch.Success | Should -BeTrue -Because "the tick decision has to be findable in controller-infra.ps1"
        $script:TickDecision = [scriptblock]::Create($regionMatch.Groups[1].Value)
    }

    It "leaves a wired tick running when rerun without the ID parameters" {
        # Rerunning controller-infra.ps1 is the documented way to finish the wiring, and it
        # used to recompute the blockers from this invocation's parameters alone. A rerun that
        # only meant to refresh a Key Vault reference therefore switched off a working tick.
        function az {
            if ($args[0] -eq "functionapp") {
                return "[{`"name`":`"GITHUB_APP_ID`",`"value`":`"1234567`"},{`"name`":`"GITHUB_INSTALLATION_ID`",`"value`":`"7654321`"}]"
            }
            "https://dbatools-fleet-kv.vault.azure.net/secrets/a-secret/0123456789abcdef"
        }
        $FunctionAppName = "dbatools-fleet-controller"
        $ResourceGroup = "dbatools-ci"
        $SubscriptionId = "00000000-0000-0000-0000-000000000000"
        $KeyVaultName = "dbatools-fleet-kv"
        $GitHubAppId = ""
        $GitHubInstallationId = ""
        $settings = @()

        . $script:TickDecision

        $settings | Should -Contain "AzureWebJobs.SafetyTick.Disabled=0"
    }

    It "keeps the tick off when the app carries nothing to run on" {
        function az {
            if ($args[0] -eq "functionapp") {
                return "[]"
            }
            ""
        }
        $FunctionAppName = "dbatools-fleet-controller"
        $ResourceGroup = "dbatools-ci"
        $SubscriptionId = "00000000-0000-0000-0000-000000000000"
        $KeyVaultName = "dbatools-fleet-kv"
        $GitHubAppId = ""
        $GitHubInstallationId = ""
        $settings = @()

        . $script:TickDecision

        $settings | Should -Contain "AzureWebJobs.SafetyTick.Disabled=1"
    }

    It "keeps the tick off while the private key is still outside Key Vault" {
        # An App ID with no key fails initialization exactly as a missing App ID does, so the
        # secrets count as blockers too
        function az {
            if ($args[0] -eq "functionapp") {
                return "[{`"name`":`"GITHUB_APP_ID`",`"value`":`"1234567`"},{`"name`":`"GITHUB_INSTALLATION_ID`",`"value`":`"7654321`"}]"
            }
            ""
        }
        $FunctionAppName = "dbatools-fleet-controller"
        $ResourceGroup = "dbatools-ci"
        $SubscriptionId = "00000000-0000-0000-0000-000000000000"
        $KeyVaultName = "dbatools-fleet-kv"
        $GitHubAppId = ""
        $GitHubInstallationId = ""
        $settings = @()

        . $script:TickDecision

        $settings | Should -Contain "AzureWebJobs.SafetyTick.Disabled=1"
    }
}

Describe "ARM token caching" {
    BeforeAll {
        $script:SavedIdentityEndpoint = $env:IDENTITY_ENDPOINT
        $script:SavedIdentityHeader = $env:IDENTITY_HEADER
        $env:IDENTITY_ENDPOINT = "http://127.0.0.1:0/msi/token"
        $env:IDENTITY_HEADER = "not-a-real-identity-header"
    }

    AfterAll {
        $env:IDENTITY_ENDPOINT = $script:SavedIdentityEndpoint
        $env:IDENTITY_HEADER = $script:SavedIdentityHeader
    }

    It "caches a token whose expiry sits past the Int32 second boundary" {
        # expires_on arrives as seconds since the epoch, and past 2038-01-19 that number no
        # longer fits in an Int32. A token that cannot parse its own expiry is one the
        # controller re-acquires on every ARM call it makes.
        InModuleScope FleetCore {
            $script:Fleet = [pscustomobject]@{
                ArmToken       = $null
                ArmTokenExpiry = [DateTimeOffset]::MinValue
            }
            $script:TokenCalls = 0
            Mock Invoke-RestMethod {
                $script:TokenCalls++
                [pscustomobject]@{
                    access_token = "arm-token-$script:TokenCalls"
                    expires_on   = "2200000000"
                }
            }

            Get-ArmToken | Should -Be "arm-token-1"
            $script:Fleet.ArmTokenExpiry | Should -Be ([DateTimeOffset]::FromUnixTimeSeconds(2200000000).AddMinutes(-5))
            Get-ArmToken | Should -Be "arm-token-1"
            $script:TokenCalls | Should -Be 1
        }
    }
}

Describe "parallel registration" {
    It "keeps the VM identity on the failure path" {
        # $PSItem is the ErrorRecord inside catch, so a result built there from $PSItem
        # would carry a null VM and silently skip the SPENT-VM delete.
        $source = Get-Content -Path "$script:ControllerRoot/Modules/FleetCore/FleetCore.psm1" -Raw
        $parallelBlock = [regex]::Match($source, "(?s)\`$results = \`$tasks \| ForEach-Object -Parallel \{.*?\} -ThrottleLimit").Value
        $parallelBlock | Should -Not -BeNullOrEmpty
        $parallelBlock | Should -Match "\`$task = \`$PSItem"
        $parallelBlock | Should -Not -Match "VmName = \`$PSItem\.VmName"
    }

    It "hands the real bootstrap script, blank lines and all, to the run-command binder" {
        # Mandatory on a [string[]] rejects the whole array when any element is an empty
        # string, and bootstrap-runner.ps1 is read line by line. Every live registration
        # failed at the binder with "because it is an empty string", and nothing caught it
        # because Test-FleetDryRun returns before this call in every non-live pass.
        $bootstrapLines = @(Get-Content -Path "$PSScriptRoot/../bootstrap-runner.ps1")
        $blankLines = @($bootstrapLines | Where-Object { $PSItem -eq "" }).Count
        $blankLines | Should -BeGreaterThan 0 -Because "this only discriminates while the bootstrap still has a blank line"
        InModuleScope FleetCore -Parameters @{ BootstrapLines = $bootstrapLines } {
            param($BootstrapLines)
            Mock Invoke-WebRequest {
                [pscustomobject]@{
                    StatusCode = 200
                    Content    = "{`"value`":[{`"message`":`"runner registered`"}]}"
                }
            }
            $splatRunCommand = @{
                ArmToken     = "arm-token"
                VmResourceId = "/subscriptions/s/resourceGroups/dbatools-ci/providers/Microsoft.Compute/virtualMachines/dbatools-runners_abc"
                ScriptLines  = $BootstrapLines
                Parameters   = @(@{ name = "Token"; value = "registration-token" })
            }
            Invoke-VmRunCommand @splatRunCommand | Should -Be "runner registered"
        }
    }
}
