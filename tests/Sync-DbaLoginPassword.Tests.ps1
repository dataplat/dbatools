$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('WhatIf', 'Confirm') }
        [object[]]$knownParameters = 'Source', 'SourceSqlCredential', 'Destination', 'DestinationSqlCredential', 'Login', 'ExcludeLogin', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}
Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        <# Optimize configuration for test runs #>
        Set-DbatoolsConfig -FullName sql.connection.timeout -Value 1 # set timeout fast so this does not run long

        $notExistLogin = "dbatoolscli_$(Get-Random)_RickAndMorty"
        $PSDefaultParameterValues.Add('Sync-DbaLoginPassword:Source', $script:instance2)
        $PSDefaultParameterValues.Add('Sync-DbaLoginPassword:Destination', $script:instance3)

        <# Create a login on both source and dest with same password, password hash should match up #>
        $testLogin1SamePwdHash = "dbatoolscli_$(Get-Random)"
        <# create the logins first with known password #>
        $query = "CREATE LOGIN $testLogin1SamePwdHash WITH PASSWORD = 'Password123', CHECK_POLICY=OFF;
        ALTER LOGIN $testLogin1SamePwdHash WITH PASSWORD = 0x02003629A14D633CBDB1AD136D32602F9AC869EEF270426935AC4FCFC2F56CFDE76E438C030CD239A832308F3ABBC9DFB72A9C8E99A00892158E172D78630DCD73D6AE706E9F HASHED;"
        Invoke-DbaQuery -SqlInstance $script:instance2, $script:instance3 -Query $query -ErrorAction Stop
    }
    AfterAll {
        $PSDefaultParameterValues.Remove('Sync-DbaLoginPassword:Source')
        $PSDefaultParameterValues.Remove('Sync-DbaLoginPassword:Destination')

        Remove-DbaLogin -SqlInstance $script:instance2, $script:instance3 -Login $testLogin1SamePwdHash -Force -Confirm:$false
    }
    Context "Verifying command output" {
        It "Should output warning if Login not found on Source" {
            Sync-DbaLoginPassword -Login $notExistLogin -WarningVariable warnTestLogin -WarningAction SilentlyContinue
            $warnTestLogin | Should -BeLike "*No matching logins found for $notExistLogin*"
        }
        It "Should output warning if Password Hash already matches" {
            Sync-DbaLoginPassword -Login $testLogin1SamePwdHash -WarningVariable warnTestHashMatch -WarningAction SilentlyContinue
            $warnTestHashMatch | Should -BeLike "*Password hash already matches for login*"
        }
    }
    Context "Verify functionality" {
        It "Should not change the password hash if matches destination" {
            $result = Sync-DbaLoginPassword -Login $testLogin1SamePwdHash -WarningAction SilentlyContinue
            $result.Status | Should -Be 'Skipped'
        }
        It "Should change the password hash on destination" {
            Set-DbaLogin -SqlInstance $script:instance3 -Login $testLogin1SamePwdHash -SecurePassword (ConvertTo-SecureString 'P@assword!123' -AsPlainText -Force)
            $result = Sync-DbaLoginPassword -Login $testLogin1SamePwdHash
            $result.Status | Should -Be 'Successful'
        }
    }
}