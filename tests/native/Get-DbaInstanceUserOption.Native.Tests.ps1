#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: whatif-confirm N/A -- the pinned command does not declare SupportsShouldProcess, so it has no -WhatIf or -Confirm.
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaInstanceUserOption",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Get-DbaInstanceUserOption" -Tag IntegrationTests {
    BeforeAll {
        $uoServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $uoTag = [guid]::NewGuid().ToString("N").Substring(0, 10)
        $uoMissing = "nf" + [guid]::NewGuid().ToString("N").Substring(0, 12)
        $uoDisplay = "ComputerName,InstanceName,SqlInstance,Name,Value"

        # Independent read: the instance's "user options" bit mask, on the test's own connection. SMO's UserOptions maps each
        # bit to one boolean property (Configure the user options server configuration option, Microsoft Learn).
        $uoMask = [int]@($uoServer.Query("SELECT CONVERT(int, value) AS v FROM sys.configurations WHERE name = N'user options'"))[0].v
        $uoBits = [ordered]@{
            DisableDefaultConstraintCheck = 1
            ImplicitTransactions          = 2
            CursorCloseOnCommit           = 4
            AnsiWarnings                  = 8
            AnsiPadding                   = 16
            AnsiNulls                     = 32
            AbortOnArithmeticErrors       = 64
            IgnoreArithmeticErrors        = 128
            QuotedIdentifier              = 256
            NoCount                       = 512
            AnsiNullDefaultOn             = 1024
            AnsiNullDefaultOff            = 2048
            ConcatenateNullYieldsNull     = 4096
            NumericRoundAbort             = 8192
            AbortTransactionOnError       = 16384
        }
    }

    It "returns each user option of the instance with the value its bit holds, decorated as the pin decorates it" {
        $results = @(Get-DbaInstanceUserOption -SqlInstance $TestConfig.InstanceSingle -ErrorVariable uoErrors)
        $uoErrors | Should -BeNullOrEmpty
        @($results.Name | Sort-Object) -join "," | Should -BeExactly (@($uoBits.Keys | Sort-Object) -join ",")
        foreach ($result in $results) {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Property]
            $result.Value | Should -BeOfType [bool]
            $result.Value | Should -Be ([bool]($uoMask -band $uoBits[$result.Name]))
            $result.ComputerName | Should -BeExactly $uoServer.ComputerName
            $result.InstanceName | Should -BeExactly $uoServer.ServiceName
            $result.SqlInstance | Should -BeExactly $uoServer.DomainInstanceName
            ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $uoDisplay
        }
    }

    It "replaces its notes when the same server's object comes back" {
        $first = Get-DbaInstanceUserOption -SqlInstance $uoServer | Where-Object Name -eq "AnsiNulls"
        $second = Get-DbaInstanceUserOption -SqlInstance $uoServer | Where-Object Name -eq "AnsiNulls"
        $second.SqlInstance | Should -BeExactly $first.SqlInstance
        foreach ($name in "ComputerName", "InstanceName", "SqlInstance") {
            @($second.PSObject.Properties | Where-Object Name -eq $name).Count | Should -Be 1
        }
    }

    It "returns the options of each piped instance and goes on past one that fails" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
        $warnings = @()
        $results = @(@($TestConfig.InstanceSingle, $uoMissing, $TestConfig.InstanceSingle) | Get-DbaInstanceUserOption -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
        $results.Count | Should -Be ($uoBits.Count * 2)
        @($results | Where-Object Name -eq "AnsiNullDefaultOff").Count | Should -Be 2
        $warnings.Count | Should -Be 1
        # One line naming the command, the failure message and the instance (brackets matched literally).
        "$($warnings[0])" | Should -Match ([regex]::Escape("[Get-DbaInstanceUserOption] Failure | Error connecting to [$uoMissing]: "))
    }

    It "reads several named instances" {
        $results = @(Get-DbaInstanceUserOption -SqlInstance $TestConfig.InstanceSingle, $TestConfig.InstanceSingle)
        $results.Count | Should -Be ($uoBits.Count * 2)
    }

    It "throws the connection failure under -EnableException" -Tag "NativeChecklist:enable-exception" {
        $caught = $null
        try {
            $null = Get-DbaInstanceUserOption -SqlInstance $uoMissing -EnableException -WarningAction SilentlyContinue
        } catch {
            $caught = $PSItem
        }
        $caught | Should -Not -BeNullOrEmpty
        $caught.CategoryInfo.Category | Should -Be "ConnectionError"
        "$($caught.TargetObject)" | Should -BeExactly $uoMissing
    }

    # The pin reads the options in its foreach, outside any try. A SQL login whose master user is denied SELECT on
    # sys.configurations connects, then SMO's read of "user options" fails. sysadmin ignores DENY, so the login has no server
    # role. It lives on the leg's own instance under a unique name and is dropped in AfterAll.
    Context "A login denied the configuration catalog" {
        BeforeAll {
            $denyName = "dbatoolsci_iuo_${uoTag}_deny"
            $denyPassword = "Iuo-" + [guid]::NewGuid().ToString("N")
            $denyCred = New-Object System.Management.Automation.PSCredential -ArgumentList $denyName, (ConvertTo-SecureString -String $denyPassword -AsPlainText -Force)
            $null = $uoServer.Query("CREATE LOGIN [$denyName] WITH PASSWORD = N'$denyPassword', CHECK_POLICY = OFF, DEFAULT_DATABASE = [master];")
            $null = $uoServer.Query("USE [master]; CREATE USER [$denyName] FOR LOGIN [$denyName]; DENY SELECT ON OBJECT::sys.configurations TO [$denyName];")

            function New-NativeDeniedServer {
                Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -SqlCredential $denyCred -NonPooledConnection -EnableException
            }

            # Independent read: the engine's own foreach over the denied collection gives the record the command must write.
            $denyReference = $null
            try {
                foreach ($denyProp in (New-NativeDeniedServer).UserOptions.Properties) { }
            } catch {
                $denyReference = $PSItem
            }

            function Assert-NativeOptionReadFault {
                param($Record)
                ($Record.FullyQualifiedErrorId -split ",")[0] | Should -BeExactly ($denyReference.FullyQualifiedErrorId -split ",")[0]
                $Record.Exception.GetType().FullName | Should -BeExactly $denyReference.Exception.GetType().FullName
                $Record.Exception.Message | Should -BeExactly $denyReference.Exception.Message
                $Record.Exception.InnerException.GetType().FullName | Should -BeExactly $denyReference.Exception.InnerException.GetType().FullName
                $Record.CategoryInfo.Category | Should -Be $denyReference.CategoryInfo.Category
                "$($Record.TargetObject)" | Should -BeExactly "$($denyReference.TargetObject)"
            }

            # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
            function Invoke-NativeOptionOutsideTry {
                param([hashtable]$Arguments)
                $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
                $outsideType = (Get-Command Get-DbaInstanceUserOption -CommandType Cmdlet).ImplementingType
                $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaInstanceUserOption", $outsideType, $null
                $outsideState.Commands.Add($outsideEntry)
                $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
                $outsideShell = [System.Management.Automation.PowerShell]::Create()
                $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
                $outsideStop = $null
                try {
                    $outsideRunspace.Open()
                    $outsideShell.Runspace = $outsideRunspace
                    $null = $outsideShell.AddScript('param($Arguments) Get-DbaInstanceUserOption @Arguments | ForEach-Object { "row: " + $PSItem.SqlInstance + " " + $PSItem.Name }; "next statement"').AddArgument($Arguments)
                    try {
                        $null = $outsideShell.Invoke($null, $outsideOutput)
                    } catch {
                        # The stop leaves the runspace's script through Invoke, as a method call's exception.
                        $outsideStop = $PSItem.Exception.InnerException
                    }
                    [pscustomobject]@{
                        Output   = @($outsideOutput | ForEach-Object { "$PSItem" })
                        Errors   = @($outsideShell.Streams.Error)
                        Warnings = @($outsideShell.Streams.Warning)
                        Stop     = $outsideStop
                    }
                } finally {
                    $outsideShell.Dispose()
                    $outsideRunspace.Dispose()
                }
            }
        }

        AfterAll {
            foreach ($row in @($uoServer.Query("SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$denyName';"))) {
                $null = $uoServer.Query("BEGIN TRY KILL $($row.session_id); END TRY BEGIN CATCH END CATCH;")
            }
            $null = $uoServer.Query("USE [master]; IF USER_ID(N'$denyName') IS NOT NULL DROP USER [$denyName];")
            $null = $uoServer.Query("IF SUSER_ID(N'$denyName') IS NOT NULL DROP LOGIN [$denyName];")
        }

        It "writes the read fault and goes on to the next instance's options, outside any try" {
            $denyReference | Should -Not -BeNullOrEmpty
            $outside = Invoke-NativeOptionOutsideTry @{ SqlInstance = @((New-NativeDeniedServer), $uoServer) }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Warnings.Count | Should -Be 0
            $outside.Errors.Count | Should -Be 1
            Assert-NativeOptionReadFault -Record $outside.Errors[0]
            $outside.Output.Count | Should -Be ($uoBits.Count + 1)
            $outside.Output | Should -Contain "row: $($uoServer.DomainInstanceName) AnsiNullDefaultOff"
            $outside.Output[-1] | Should -BeExactly "next statement"
        }

        It "writes each instance's read fault, outside any try" {
            $outside = Invoke-NativeOptionOutsideTry @{ SqlInstance = @((New-NativeDeniedServer), (New-NativeDeniedServer)) }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 2
            foreach ($record in $outside.Errors) {
                Assert-NativeOptionReadFault -Record $record
            }
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        # Keep-going rule: -EnableException stops at the record (corrections.json, acceptedDifferences).
        It "stops at the first read fault under -EnableException, and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeOptionOutsideTry @{ SqlInstance = @((New-NativeDeniedServer), $uoServer); EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeOptionReadFault -Record $outside.Errors[0]
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        It "lets a caller's try catch the read fault, and the command does not go on" {
            $first = New-NativeDeniedServer
            $callerOutput = @(try { Get-DbaInstanceUserOption -SqlInstance $first, $uoServer; "after" } catch { $_ })
            $callerOutput.Count | Should -Be 1
            $callerOutput[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
            Assert-NativeOptionReadFault -Record $callerOutput[0]
        }

        It "stops at the read fault under -ErrorAction Stop, outside a try" {
            $outside = Invoke-NativeOptionOutsideTry @{ SqlInstance = @((New-NativeDeniedServer), $uoServer); ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-NativeOptionReadFault -Record $outside.Stop.ErrorRecord
            $outside.Output.Count | Should -Be 0
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            # Read-only on the shared SQL-login instance: nothing is created there.
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
        }

        It "works with -SqlCredential" {
            $result = @(Get-DbaInstanceUserOption -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException -ErrorVariable loginErrors)
            $loginErrors | Should -BeNullOrEmpty
            $result.Count | Should -Be $uoBits.Count
            foreach ($row in $result) {
                $row | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Property]
                $row.SqlInstance | Should -BeExactly $loginServer.DomainInstanceName
            }
        }

        It "fails cleanly without the credential: a warning and no output" {
            $warnings = @()
            $result = Get-DbaInstanceUserOption -SqlInstance $loginInstance -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warnings | Should -Not -BeNullOrEmpty
        }

        It "throws without the credential under -EnableException, as the pinned Stop-Function does" {
            { Get-DbaInstanceUserOption -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue } | Should -Throw
        }
    }

    Context "Azure SQL Database" -Tag NativeChecklist:azure-sqldb {
        BeforeAll {
            $azure = $null
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    $azure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -Database $TestConfig.AzureSqlDbName -SqlCredential $TestConfig.AzureSqlDbCred -EnableException
                    break
                } catch {
                    $azureError = $PSItem.Exception
                    $isResuming = $false
                    while ($azureError) {
                        if ($azureError.Number -in 40613, -2 -or $azureError -is [System.TimeoutException]) { $isResuming = $true }
                        # "The wait operation timed out": a resuming database's handshake timeout, an inner Win32Exception 258.
                        if ($azureError -is [System.ComponentModel.Win32Exception] -and $azureError.NativeErrorCode -eq 258) { $isResuming = $true }
                        $azureError = $azureError.InnerException
                    }
                    if (-not $isResuming -or $attempt -eq 6) { throw }
                    Start-Sleep -Seconds 10
                }
            }
        }

        AfterAll {
            if ($azure) { $azure.ConnectionContext.Disconnect() }
        }

        # SMO reads the options there as on an instance, from the same catalog row: pin probe 6729751f
        # (evidence/pin-useroption-6729751f-20261105.txt, 5.1 and 7.6.5) gave 15 rows, all False, with sys.configurations
        # holding 'user options' 0, and no record or warning, plainly and under -EnableException, in master and in a user
        # database. The port returns them as the pin does.
        It "returns the user options of Azure SQL Database with the values its catalog holds" {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $azureMask = [int]@($azure.Query("SELECT CONVERT(int, value) AS v FROM sys.configurations WHERE name = N'user options'"))[0].v
            $results = @(Get-DbaInstanceUserOption -SqlInstance $azure -EnableException)
            @($results.Name | Sort-Object) -join "," | Should -BeExactly (@($uoBits.Keys | Sort-Object) -join ",")
            foreach ($result in $results) {
                $result | Should -BeOfType [Microsoft.SqlServer.Management.Smo.Property]
                $result.Value | Should -Be ([bool]($azureMask -band $uoBits[$result.Name]))
                $result.SqlInstance | Should -BeExactly $azure.DomainInstanceName
                ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $uoDisplay
            }
        }
    }
}
