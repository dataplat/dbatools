#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaSsisCatalog",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Should not declare ShouldProcess" {
            (Get-Command $CommandName).Parameters.Keys | Should -Not -Contain "WhatIf"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        $ssisInstance = $TestConfig.InstanceSsis
        # catalog.catalog_properties is a view over this table, so a row inserted here is a
        # property name that no released catalog build defines and that the command therefore
        # cannot have been written knowing about.
        $probeProperty = "DBATOOLSCI_PROBE_PROPERTY"
        $probePascal   = "DbatoolsciProbeProperty"
        $probeValue    = "dbatoolsci-probe-value"

        $splatProbeSetup = @{
            SqlInstance  = $ssisInstance
            Database     = "SSISDB"
            Query        = "
                IF NOT EXISTS (SELECT 1 FROM [internal].[catalog_properties] WHERE property_name = @name)
                    INSERT INTO [internal].[catalog_properties] (property_name, property_value) VALUES (@name, @value);"
            SqlParameter = @{
                name  = $probeProperty
                value = $probeValue
            }
        }
        Invoke-DbaQuery @splatProbeSetup

        $splatPropertyRead = @{
            SqlInstance = $ssisInstance
            Database    = "SSISDB"
            Query       = "SELECT property_name, property_value FROM [catalog].[catalog_properties]"
        }
        $catalogPropertyRows = @(Invoke-DbaQuery @splatPropertyRead)

        $catalog = @(Get-DbaSsisCatalog -SqlInstance $ssisInstance)
    }

    AfterAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        $splatProbeTeardown = @{
            SqlInstance  = $TestConfig.InstanceSsis
            Database     = "SSISDB"
            Query        = "DELETE FROM [internal].[catalog_properties] WHERE property_name = @name;"
            SqlParameter = @{
                name = "DBATOOLSCI_PROBE_PROPERTY"
            }
        }
        Invoke-DbaQuery @splatProbeTeardown
    }

    Context "Reading the catalog" {
        It "Returns one object for an instance that hosts a catalog" {
            $catalog.Count | Should -Be 1
            $catalog[0].Name | Should -Be "SSISDB"
        }

        It "Reports the catalog properties this build defines" {
            $catalog[0].SchemaVersion | Should -Not -BeNullOrEmpty
            $catalog[0].SchemaBuild | Should -Not -BeNullOrEmpty
            $catalog[0].EncryptionAlgorithm | Should -Not -BeNullOrEmpty
            foreach ($expectedProperty in @("DefaultExecutionMode", "MaxProjectVersions", "OperationCleanupEnabled", "RetentionWindow", "ServerCustomizedLoggingLevel", "ServerLoggingLevel", "ServerOperationEncryptionLevel", "VersionCleanupEnabled")) {
                $catalog[0].PSObject.Properties.Name | Should -Contain $expectedProperty
            }
        }

        It "Accepts the instance from the pipeline" {
            $piped = @($ssisInstance | Get-DbaSsisCatalog)
            $piped.Count | Should -Be 1
            $piped[0].Name | Should -Be "SSISDB"
        }
    }

    Context "The pivot is driven by the view, not by a fixed list" {
        It "Emits a property the command cannot have known about" {
            $catalog[0].PSObject.Properties.Name | Should -Contain $probePascal
            $catalog[0].$probePascal | Should -Be $probeValue
        }

        It "Emits every row the view returns, PascalCased from its underscore form" {
            $catalogPropertyRows.Count | Should -BeGreaterThan 10
            foreach ($propertyRow in $catalogPropertyRows) {
                $pascalName = ($propertyRow.property_name -split "_" | ForEach-Object { $PSItem.Substring(0, 1).ToUpperInvariant() + $PSItem.Substring(1).ToLowerInvariant() }) -join ""
                $catalog[0].PSObject.Properties.Name | Should -Contain $pascalName
                $catalog[0].$pascalName | Should -Be $propertyRow.property_value
            }
        }
    }

    Context "Output decoration" {
        It "Carries the instance property triple" {
            $catalog[0].ComputerName | Should -Not -BeNullOrEmpty
            $catalog[0].InstanceName | Should -Not -BeNullOrEmpty
            $catalog[0].SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "Carries the dbatools.SsisCatalog type name" {
            $catalog[0].PSObject.TypeNames[0] | Should -Be "dbatools.SsisCatalog"
        }

        It "Keeps the wider property set off the default view" {
            $displaySet = $catalog[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $displaySet | Should -Contain "Name"
            $displaySet | Should -Contain "SchemaVersion"
            $displaySet | Should -Contain "EncryptionAlgorithm"
            $displaySet | Should -Not -Contain "RetentionWindow"
            $catalog[0].PSObject.Properties.Name | Should -Contain "RetentionWindow"
        }
    }

    Context "An instance with no SSIS catalog" {
        # InstanceSingle carries no SSISDB, so this exercises the presence check rather than
        # failing inside the catalog schema.
        It "Warns and returns nothing" {
            $splatNoCatalog = @{
                SqlInstance     = $TestConfig.InstanceSingle
                EnableException = $false
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $none = @(Get-DbaSsisCatalog @splatNoCatalog)
            $none.Count | Should -Be 0
            ($warn -join " ") | Should -BeLike "*No SSIS catalog (SSISDB) found*"
        }

        It "Throws under -EnableException" {
            { Get-DbaSsisCatalog -SqlInstance $TestConfig.InstanceSingle -EnableException } | Should -Throw "*No SSIS catalog (SSISDB) found*"
        }
    }
}
