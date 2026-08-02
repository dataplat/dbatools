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
}
