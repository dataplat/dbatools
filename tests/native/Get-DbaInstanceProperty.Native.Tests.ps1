#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaInstanceProperty",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads SMO's Information, UserOptions and Settings properties.

# A failed connect writes one warning line naming the server: harness-edits.md, "Script-scope preferences and the one-line connect warning".

Describe "Native Get-DbaInstanceProperty" -Tag IntegrationTests {
    BeforeAll {
        $instance = $TestConfig.InstanceSingle
        $missingInstance = "nativeinstanceproperty$(Get-Random)"
        # The fixture's connection is never given to the command; it gives the expected names in SMO's order.
        $fixture = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection -EnableException
        $expected = @(
            foreach ($prop in $fixture.Information.Properties) { "Information/$($prop.Name)" }
            foreach ($prop in $fixture.UserOptions.Properties) { "UserOption/$($prop.Name)" }
            foreach ($prop in $fixture.Settings.Properties) { "Setting/$($prop.Name)" }
        )
        $allNames = @($expected | ForEach-Object { ($PSItem -split "/", 2)[1] })
    }

    AfterAll {
        $fixture.ConnectionContext.Disconnect()
    }

    Context "Output" {
        BeforeAll {
            $results = @(Get-DbaInstanceProperty -SqlInstance $instance -EnableException)
        }

        It "returns every Information, UserOptions and Settings property, in that order" {
            $expected.Count | Should -BeGreaterThan 0
            @($results | ForEach-Object { "$($PSItem.PropertyType)/$($PSItem.Name)" }) | Should -Be $expected
        }

        It "adds the pinned note properties and default view" {
            ($results[0] | Get-Member -MemberType NoteProperty).Name | Sort-Object | Should -Be @("ComputerName", "InstanceName", "PropertyType", "SqlInstance")
            $results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Should -Be @("ComputerName", "InstanceName", "SqlInstance", "Name", "Value", "PropertyType")
            $results[0].psobject.BaseObject | Should -BeOfType Microsoft.SqlServer.Management.Smo.Property
            $results[0].ComputerName | Should -BeExactly $fixture.ComputerName
            $results[0].InstanceName | Should -BeExactly $fixture.ServiceName
            $results[0].SqlInstance | Should -BeExactly $fixture.DomainInstanceName
        }

        It "reports the values the server reports" {
            $engine = $fixture.Query("SELECT CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(128)) AS ProductVersion, CAST(SERVERPROPERTY('Collation') AS nvarchar(128)) AS Collation")
            ($results | Where-Object Name -eq "VersionString").Value | Should -BeExactly $engine.ProductVersion
            ($results | Where-Object Name -eq "Collation").Value | Should -BeExactly $engine.Collation
            ($results | Where-Object Name -eq "DefaultFile").PropertyType | Should -BeExactly "Setting"
        }
    }

    Context "-InstanceProperty and -ExcludeInstanceProperty" {
        It "returns only the property named, whatever its case" {
            $results = @(Get-DbaInstanceProperty -SqlInstance $instance -InstanceProperty defaultfile -EnableException)
            @($results.Name) | Should -Be @("DefaultFile")
            $results[0].PropertyType | Should -BeExactly "Setting"
        }

        It "returns each property named, in SMO's order" {
            $results = @(Get-DbaInstanceProperty -SqlInstance $instance -InstanceProperty LoginMode, Edition -EnableException)
            @($results | ForEach-Object { "$($PSItem.PropertyType)/$($PSItem.Name)" }) | Should -Be @($expected | Where-Object { $PSItem -in "Information/Edition", "Setting/LoginMode" })
        }

        It "treats an empty -InstanceProperty as no filter" {
            @(Get-DbaInstanceProperty -SqlInstance $instance -InstanceProperty "" -EnableException).Count | Should -Be $expected.Count
        }

        It "leaves out the property excluded" {
            $results = @(Get-DbaInstanceProperty -SqlInstance $instance -ExcludeInstanceProperty DefaultFile -EnableException)
            $results.Count | Should -Be ($expected.Count - 1)
            @($results.Name) | Should -Not -Contain "DefaultFile"
        }

        It "matches -InstanceProperty wildcards, as the help documents" {
            $wanted = @($expected | Where-Object { ($PSItem -split "/", 2)[1] -like "Default*" })
            $wanted.Count | Should -BeGreaterThan 1
            $results = @(Get-DbaInstanceProperty -SqlInstance $instance -InstanceProperty "Default*" -EnableException)
            @($results | ForEach-Object { "$($PSItem.PropertyType)/$($PSItem.Name)" }) | Should -Be $wanted
            @(Get-DbaInstanceProperty -SqlInstance $instance -InstanceProperty "DefaultFil?" -EnableException).Name | Should -Be @("DefaultFile")
        }

        It "matches -ExcludeInstanceProperty wildcards, as the help documents" {
            $kept = @($expected | Where-Object { ($PSItem -split "/", 2)[1] -notlike "Default*" })
            $results = @(Get-DbaInstanceProperty -SqlInstance $instance -ExcludeInstanceProperty "Default*" -EnableException)
            @($results | ForEach-Object { "$($PSItem.PropertyType)/$($PSItem.Name)" }) | Should -Be $kept
        }
    }

    Context "Instances" {
        It "reads each piped instance" -Tag "NativeChecklist:pipeline-multiple" {
            $results = @($instance, $instance | Get-DbaInstanceProperty -InstanceProperty Edition -EnableException)
            $results.Count | Should -Be 2
            @($results.Name) | Should -Be @("Edition", "Edition")
        }

        It "reads through a server object" {
            $own = Connect-DbaInstance -SqlInstance $instance -EnableException
            $result = @($own | Get-DbaInstanceProperty -InstanceProperty Edition -EnableException)
            $result.Count | Should -Be 1
            $result[0].SqlInstance | Should -BeExactly $own.DomainInstanceName
        }
    }

    Context "An instance that cannot be reached" {
        It "warns and goes on to the next instance" -Tag "NativeChecklist:multi-instance-failure" {
            $warnings = $null
            $results = @(Get-DbaInstanceProperty -SqlInstance $missingInstance, $instance -InstanceProperty Edition -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 1
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match ([regex]::Escape("[Get-DbaInstanceProperty] Failure | Error connecting to [$missingInstance]: "))
        }

        It "warns and goes on under -EnableException:`$false" -Tag "NativeChecklist:switch-false" {
            $warnings = $null
            $results = @(Get-DbaInstanceProperty -SqlInstance $missingInstance, $instance -InstanceProperty Edition -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 1
            @($warnings).Count | Should -Be 1
        }

        It "throws the connection failure under -EnableException, before the next instance" -Tag "NativeChecklist:enable-exception" {
            $caught = $null
            $collected = $null
            $warnings = $null
            try {
                $null = Get-DbaInstanceProperty -SqlInstance $missingInstance, $instance -InstanceProperty Edition -EnableException -OutVariable collected -WarningVariable warnings -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match ([regex]::Escape("[Get-DbaInstanceProperty] Failure | Error connecting to [$missingInstance]: "))
            $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaInstanceProperty*"
            "$($caught.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
            "$($caught.TargetObject)" | Should -BeExactly $missingInstance
            @($collected).Count | Should -Be 0
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
        }

        It "works with -SqlCredential" {
            $result = @(Get-DbaInstanceProperty -SqlInstance $loginInstance -SqlCredential $loginCred -InstanceProperty Edition -EnableException)
            $result.Count | Should -Be 1
            $result[0].PropertyType | Should -BeExactly "Information"
        }

        It "fails cleanly without the credential: a warning and no output" {
            $warnings = $null
            $result = Get-DbaInstanceProperty -SqlInstance $loginInstance -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match ([regex]::Escape("[Get-DbaInstanceProperty] Failure | Error connecting to [$loginInstance]: Login failed"))
        }

        # The pin connects in its own try and Stop-Function throws there under -EnableException.
        It "throws the connection failure under -EnableException" {
            { Get-DbaInstanceProperty -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue } | Should -Throw -ExpectedMessage "*Login failed*" -ErrorId "dbatools_Get-DbaInstanceProperty*"
        }
    }
}

# As the pin measured on both editions (evidence/pin-instanceproperty-6d295104-20261105.txt): on Azure SQL Database SMO reports the
# Information and UserOptions properties and no Settings property, and the pin returns those rows with no warning or error.
Describe "Native Get-DbaInstanceProperty on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $azureDatabase = $TestConfig.AzureSqlDbName
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $azureDatabase
            SqlCredential   = $TestConfig.AzureSqlDbCred
            EnableException = $true
        }
        function Connect-NativeAzure {
            $connected = $null
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    $connected = Connect-DbaInstance @splatAzureConnection
                    break
                } catch {
                    # A paused serverless database answers 40613 or times out while it resumes, and the lab's mobile internet can drop a name lookup (11001).
                    $azureError = $PSItem.Exception
                    $isResuming = "$($PSItem.Exception.Message)" -like "*timed out*"
                    while ($azureError) {
                        if ($azureError.Number -in 40613, -2, 258, 11001 -or $azureError -is [System.TimeoutException]) { $isResuming = $true }
                        $azureError = $azureError.InnerException
                    }
                    if (-not $isResuming -or $attempt -eq 6) { throw }
                    Start-Sleep -Seconds 10
                }
            }
            $connected
        }
        $azureFixture = Connect-NativeAzure
        $azureExpected = @(
            foreach ($prop in $azureFixture.Information.Properties) { "Information/$($prop.Name)" }
            foreach ($prop in $azureFixture.UserOptions.Properties) { "UserOption/$($prop.Name)" }
            foreach ($prop in $azureFixture.Settings.Properties) { "Setting/$($prop.Name)" }
        )
    }

    # Read-only.
    It "returns the Information and UserOptions properties through a server object, with no warning" -Tag "NativeChecklist:azure-sqldb" {
        $azureFixture.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $azureServer = Connect-NativeAzure
        $warnings = $null
        $results = @(Get-DbaInstanceProperty -SqlInstance $azureServer -WarningVariable warnings -WarningAction SilentlyContinue)
        @($warnings).Count | Should -Be 0
        @($azureExpected | Where-Object { $PSItem -like "Information/*" }).Count | Should -BeGreaterThan 0
        @($azureExpected | Where-Object { $PSItem -like "UserOption/*" }).Count | Should -BeGreaterThan 0
        @($results | ForEach-Object { "$($PSItem.PropertyType)/$($PSItem.Name)" }) | Should -Be $azureExpected
        $results[0].ComputerName | Should -BeExactly $azureServer.ComputerName
        $results[0].SqlInstance | Should -BeExactly $azureServer.DomainInstanceName
        $results[0].InstanceName | Should -BeNullOrEmpty
        $engine = $azureServer.Query("SELECT CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(128)) AS ProductVersion")
        ($results | Where-Object Name -eq "VersionString").Value | Should -BeExactly $engine.ProductVersion
    }

    It "returns the same rows on a connection by name, and under -EnableException" -Tag "NativeChecklist:azure-sqldb" {
        $null = Connect-NativeAzure
        $results = @(Get-DbaInstanceProperty -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -EnableException)
        @($results | ForEach-Object { "$($PSItem.PropertyType)/$($PSItem.Name)" }) | Should -Be $azureExpected
    }
}
