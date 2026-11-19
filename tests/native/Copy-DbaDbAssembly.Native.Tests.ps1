#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Copy-DbaDbAssembly",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: pipeline-multiple N/A -- no parameter accepts pipeline input.
# NativeChecklist: azure-sqldb N/A -- Azure SQL Database does not support user CLR assemblies; refuse through AzureUnsupported. https://learn.microsoft.com/data-migration/sql-server/database/assessment-rules#clr-assemblies
Describe "Native Copy-DbaDbAssembly corrections" -Tag IntegrationTests {
    BeforeAll {
        $assemblySuffix = [guid]::NewGuid().ToString("N")
        $assemblySource = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -EnableException
        $assemblyDestination = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2 -EnableException
        $assemblyDatabases = New-Object System.Collections.Generic.List[object]
        $assemblyTrustAdded = @()
        function Get-AssemblyIdentifier([string]$Name) { "[" + $Name.Replace("]", "]]") + "]" }
        function Get-AssemblyLiteral([string]$Value) { "N'" + $Value.Replace("'", "''") + "'" }
        $assemblyPinPath = Join-Path (Split-Path $PSScriptRoot) "Copy-DbaDbAssembly.Tests.ps1"
        $assemblyFixtureText = Get-Content -LiteralPath $assemblyPinPath -Raw
        $assemblyMatch = [regex]::Match($assemblyFixtureText, "CREATE ASSEMBLY \[resolveDNS\] AUTHORIZATION \[dbo\] FROM (0x[0-9A-Fa-f]+)")
        if (-not $assemblyMatch.Success) { throw "Pinned CLR assembly fixture was not found." }
        $assemblyHex = $assemblyMatch.Groups[1].Value
        $assemblyHash = $assemblySource.ConnectionContext.ExecuteScalar("SELECT CONVERT(varchar(130), HASHBYTES('SHA2_512', $assemblyHex), 1);")
        foreach ($assemblyServer in @($assemblySource, $assemblyDestination)) {
            $assemblyRegistered = $assemblyServer.ConnectionContext.ExecuteScalar("SELECT COUNT(*) FROM sys.trusted_assemblies WHERE hash = $assemblyHash;")
            if ($assemblyRegistered -eq 0) {
                $null = $assemblyServer.ConnectionContext.ExecuteNonQuery("EXEC sys.sp_add_trusted_assembly @hash = $assemblyHash, @description = N'native_assembly_$assemblySuffix';")
                $assemblyTrustAdded += $assemblyServer
            }
        }
        function New-AssemblyCase {
            param([string]$Suffix, [string]$Name = "native_assembly", [switch]$SourceOn, [switch]$DestinationOn, [switch]$Existing, [switch]$Safe)
            $caseDatabase = "native_assembly_${assemblySuffix}_$Suffix"
            $caseSource = New-Object Microsoft.SqlServer.Management.Smo.Database($assemblySource, $caseDatabase)
            $caseSource.Create()
            $assemblyDatabases.Add([pscustomobject]@{ Server = $assemblySource; Name = $caseDatabase })
            $caseDestination = New-Object Microsoft.SqlServer.Management.Smo.Database($assemblyDestination, $caseDatabase)
            $caseDestination.Create()
            $assemblyDatabases.Add([pscustomobject]@{ Server = $assemblyDestination; Name = $caseDatabase })
            $caseIdentifier = Get-AssemblyIdentifier $caseDatabase
            $casePermission = "EXTERNAL_ACCESS"
            if ($Safe) { $casePermission = "SAFE" }
            $caseAssemblyIdentifier = Get-AssemblyIdentifier $Name
            $caseSql = "CREATE ASSEMBLY $caseAssemblyIdentifier AUTHORIZATION [dbo] FROM $assemblyHex WITH PERMISSION_SET = $casePermission;"
            if (-not $Safe) { $null = $assemblySource.ConnectionContext.ExecuteNonQuery("ALTER DATABASE $caseIdentifier SET TRUSTWORTHY ON;") }
            $caseSource.ExecuteNonQuery($caseSql)
            $sourceTrust = if ($SourceOn) { "ON" } else { "OFF" }
            $null = $assemblySource.ConnectionContext.ExecuteNonQuery("ALTER DATABASE $caseIdentifier SET TRUSTWORTHY $sourceTrust;")
            if ($Existing) {
                if (-not $Safe) { $null = $assemblyDestination.ConnectionContext.ExecuteNonQuery("ALTER DATABASE $caseIdentifier SET TRUSTWORTHY ON;") }
                $caseDestination.ExecuteNonQuery($caseSql)
            }
            $destinationTrust = if ($DestinationOn) { "ON" } else { "OFF" }
            $null = $assemblyDestination.ConnectionContext.ExecuteNonQuery("ALTER DATABASE $caseIdentifier SET TRUSTWORTHY $destinationTrust;")
            $caseSource.Refresh()
            $caseDestination.Refresh()
            [pscustomobject]@{ Database = $caseDatabase; Name = $Name; Source = $caseSource; Destination = $caseDestination; CreateSql = $caseSql }
        }
        function Get-AssemblySqlErrorNumber($Exception) {
            while ($Exception) {
                if ($null -ne $Exception.Number) { return [int]$Exception.Number }
                $Exception = $Exception.InnerException
            }
        }
        function Get-AssemblyTrust($Server, [string]$Database) {
            $databaseLiteral = Get-AssemblyLiteral $Database
            $Server.ConnectionContext.ExecuteScalar("SELECT is_trustworthy_on FROM sys.databases WHERE name = $databaseLiteral;")
        }
        function Invoke-AssemblyCase($Case, [switch]$Force, [switch]$WhatIf) {
            $splatCase = @{
                Source          = $assemblySource
                Destination     = $assemblyDestination
                Assembly        = "$($Case.Database).$($Case.Name)"
                Force           = $Force
                WhatIf          = $WhatIf
                Confirm         = $false
                EnableException = $true
            }
            Copy-DbaDbAssembly @splatCase
        }
    }

    AfterAll {
        foreach ($assemblyDatabase in $assemblyDatabases) {
            $assemblyDatabase.Server.KillDatabase($assemblyDatabase.Name)
        }
        foreach ($assemblyServer in $assemblyTrustAdded) {
            $null = $assemblyServer.ConnectionContext.ExecuteNonQuery("EXEC sys.sp_drop_trusted_assembly @hash = $assemblyHash;")
        }
    }

    It "mirrors source trust only when an external assembly needs an untrusted destination" {
        $offCase = New-AssemblyCase -Suffix "off"
        Get-AssemblyTrust $assemblySource $offCase.Database | Should -BeFalse
        Get-AssemblyTrust $assemblyDestination $offCase.Database | Should -BeFalse
        $offExpectedStatus = "Successful"
        $offControlError = $null
        try {
            $offCase.Destination.ExecuteNonQuery($offCase.CreateSql)
        } catch {
            $offControlError = Get-AssemblySqlErrorNumber $PSItem.Exception
            if ($offControlError -ne 10327) { throw }
            $offExpectedStatus = "Failed"
        }
        if ($offExpectedStatus -eq "Successful") {
            $offIdentifier = Get-AssemblyIdentifier $offCase.Name
            $offCase.Destination.ExecuteNonQuery("DROP ASSEMBLY $offIdentifier;")
        }
        $offCase.Destination.Assemblies.Refresh()
        Get-AssemblyTrust $assemblyDestination $offCase.Database | Should -BeFalse
        $offResult = @(Invoke-AssemblyCase $offCase)
        $offResult.Count | Should -Be 1
        $offResult[0].Status | Should -Be $offExpectedStatus
        Get-AssemblyTrust $assemblyDestination $offCase.Database | Should -BeFalse
        $offLiteral = Get-AssemblyLiteral $offCase.Name
        if ($offExpectedStatus -eq "Successful") {
            $offContent = $offCase.Destination.ExecuteWithResults("SELECT CONVERT(varchar(130), HASHBYTES('SHA2_512', f.content), 1) AS AssemblyHash FROM sys.assembly_files f JOIN sys.assemblies a ON a.assembly_id=f.assembly_id WHERE a.name=$offLiteral AND f.file_id=1;").Tables[0].Rows
            $offContent.Count | Should -Be 1
            $offContent[0].AssemblyHash | Should -Be $assemblyHash
        } else {
            $offResult[0].Notes | Should -BeOfType "System.Management.Automation.ErrorRecord"
            Get-AssemblySqlErrorNumber $offResult[0].Notes.Exception | Should -Be $offControlError
            $offCase.Destination.Assemblies.Refresh()
            $offCase.Destination.Assemblies[$offCase.Name] | Should -BeNullOrEmpty
        }
        $onCase = New-AssemblyCase -Suffix "on" -SourceOn
        Get-AssemblyTrust $assemblySource $onCase.Database | Should -BeTrue
        Get-AssemblyTrust $assemblyDestination $onCase.Database | Should -BeFalse
        $onResult = @(Invoke-AssemblyCase $onCase)
        $onResult.Count | Should -Be 1
        $onResult[0].Status | Should -Be "Successful"
        Get-AssemblyTrust $assemblyDestination $onCase.Database | Should -BeTrue
    }

    It "leaves trust unchanged when an existing assembly is skipped" -Tag NativeChecklist:switch-false {
        $skipCase = New-AssemblyCase -Suffix "skip" -SourceOn -Existing
        Get-AssemblyTrust $assemblyDestination $skipCase.Database | Should -BeFalse
        $skipResult = @(Invoke-AssemblyCase $skipCase -Force:$false)
        $skipResult.Count | Should -Be 1
        $skipResult[0].Status | Should -Be "Skipped"
        $skipResult[0].Notes | Should -Be "Already exists on destination"
        Get-AssemblyTrust $assemblyDestination $skipCase.Database | Should -BeFalse
    }

    It "quotes the database identifier when copying source trust" {
        $quotedCase = New-AssemblyCase -Suffix "quoted ]' db" -SourceOn
        $quotedResult = @(Invoke-AssemblyCase $quotedCase)
        $quotedResult.Count | Should -Be 1
        $quotedResult[0].Status | Should -Be "Successful"
        Get-AssemblyTrust $assemblyDestination $quotedCase.Database | Should -BeTrue
        $quotedCase.Destination.Assemblies.Refresh()
        $quotedCase.Destination.Assemblies[$quotedCase.Name] | Should -Not -BeNullOrEmpty
    }

    It "copies and replaces an assembly whose name requires quoting" {
        $nameCase = New-AssemblyCase -Suffix "name" -Name "native ]' assembly" -Existing -Safe
        $nameLiteral = Get-AssemblyLiteral $nameCase.Name
        $nameCase.Destination.ExecuteNonQuery("EXEC sys.sp_addextendedproperty @name=N'native_before', @value=1, @level0type=N'ASSEMBLY', @level0name=$nameLiteral;")
        $nameResult = @(Invoke-AssemblyCase $nameCase -Force)
        $nameResult.Count | Should -Be 1
        $nameResult[0].Status | Should -Be "Successful"
        $nameData = $nameCase.Destination.ExecuteWithResults("SELECT a.name, CONVERT(varchar(130), HASHBYTES('SHA2_512', f.content), 1) AS AssemblyHash FROM sys.assemblies a JOIN sys.assembly_files f ON a.assembly_id=f.assembly_id WHERE a.name=$nameLiteral AND f.file_id=1;").Tables[0].Rows
        $nameData.Count | Should -Be 1
        $nameData[0].name | Should -BeExactly $nameCase.Name
        $nameData[0].AssemblyHash | Should -Be $assemblyHash
        $nameCase.Destination.ExecuteWithResults("SELECT COUNT(*) AS PropertyCount FROM sys.extended_properties p JOIN sys.assemblies a ON a.assembly_id=p.major_id WHERE p.class=5 AND a.name=$nameLiteral AND p.name=N'native_before';").Tables[0].Rows[0].PropertyCount | Should -Be 0
    }

    It "preserves an already trustworthy destination" {
        $trustedCase = New-AssemblyCase -Suffix "trusted" -DestinationOn
        $trustedResult = @(Invoke-AssemblyCase $trustedCase)
        $trustedResult.Count | Should -Be 1
        $trustedResult[0].Status | Should -Be "Successful"
        Get-AssemblyTrust $assemblyDestination $trustedCase.Database | Should -BeTrue
    }

    It "continues to a healthy destination after a connection failure" -Tag NativeChecklist:multi-instance-failure, NativeChecklist:enable-exception {
        $continueCase = New-AssemblyCase -Suffix "continue" -Safe
        $splatContinueAssembly = @{
            Source          = $assemblySource
            Destination     = @("tcp:127.0.0.1,1", $assemblyDestination)
            Assembly        = "$($continueCase.Database).$($continueCase.Name)"
            Confirm         = $false
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "assemblyWarnings"
        }
        $assemblyWarnings = @()
        $continueResult = @(Copy-DbaDbAssembly @splatContinueAssembly)
        $assemblyWarnings | Should -Not -BeNullOrEmpty
        $continueResult.Count | Should -Be 1
        $continueResult[0].Status | Should -Be "Successful"
        $continueCase.Destination.Assemblies.Refresh()
        $continueCase.Destination.Assemblies[$continueCase.Name] | Should -Not -BeNullOrEmpty
    }

    It "refuses Azure SQL Database before enumerating CLR assemblies" {
        $assemblyAzure = $null
        try {
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    $assemblyAzure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -Database $TestConfig.AzureSqlDbName -SqlCredential $TestConfig.AzureSqlDbCred -EnableException
                    break
                } catch {
                    $azureError = $_.Exception
                    $isResuming = $false
                    while ($azureError) {
                        if ($azureError.Number -in 40613, -2 -or $azureError -is [System.TimeoutException]) { $isResuming = $true }
                        $azureError = $azureError.InnerException
                    }
                    if (-not $isResuming -or $attempt -eq 6) { throw }
                    Start-Sleep -Seconds 10
                }
            }
            $assemblyAzure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $sourceRefusal = @(Copy-DbaDbAssembly -Source $assemblyAzure -Destination $assemblyDestination -EnableException:$false -Confirm:$false -WarningAction SilentlyContinue -WarningVariable assemblySourceWarning)
            $sourceRefusal.Count | Should -Be 0
            ($assemblySourceWarning -join " ") | Should -BeLike "*Azure SQL Database not supported*"
            $azureCase = New-AssemblyCase -Suffix "azure" -Safe
            $destinationRefusal = @(Copy-DbaDbAssembly -Source $assemblySource -Destination @($assemblyAzure, $assemblyDestination) -Assembly "$($azureCase.Database).$($azureCase.Name)" -EnableException:$false -Confirm:$false -WarningAction SilentlyContinue -WarningVariable assemblyDestinationWarning)
            $destinationRefusal.Count | Should -Be 1
            $destinationRefusal[0].Status | Should -Be "Successful"
            ($assemblyDestinationWarning -join " ") | Should -BeLike "*Azure SQL Database not supported*"
            $azureCase.Destination.Assemblies.Refresh()
            $azureCase.Destination.Assemblies[$azureCase.Name] | Should -Not -BeNullOrEmpty
        } finally {
            if ($assemblyAzure) { $assemblyAzure.ConnectionContext.Disconnect() }
        }
    }

    It "throws for a failed connection with EnableException" -Tag NativeChecklist:enable-exception {
        $splatThrowAssembly = @{
            Source          = $assemblySource
            Destination     = "tcp:127.0.0.1,1"
            Assembly        = "none.none"
            Confirm         = $false
            EnableException = $true
        }
        { Copy-DbaDbAssembly @splatThrowAssembly } | Should -Throw
    }

    It "performs no trust change or assembly creation under WhatIf" -Tag NativeChecklist:whatif-confirm {
        $whatIfCase = New-AssemblyCase -Suffix "whatif" -SourceOn
        @(Invoke-AssemblyCase $whatIfCase -WhatIf).Count | Should -Be 0
        Get-AssemblyTrust $assemblyDestination $whatIfCase.Database | Should -BeFalse
        $whatIfCase.Destination.Assemblies.Refresh()
        $whatIfCase.Destination.Assemblies[$whatIfCase.Name] | Should -BeNullOrEmpty
    }
}
