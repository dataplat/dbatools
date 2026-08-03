#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaSsisCatalog",
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
                "RetentionWindow",
                "MaxProjectVersions",
                "ServerLoggingLevel",
                "ServerCustomizedLoggingLevel",
                "ServerOperationEncryptionLevel",
                "DefaultExecutionMode",
                "EncryptionAlgorithm",
                "OperationCleanupEnabled",
                "VersionCleanupEnabled",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Should declare ShouldProcess" {
            (Get-Command $CommandName).Parameters.Keys | Should -Contain "WhatIf"
        }

        It "Should take the boolean properties as switches" {
            # A [bool] would make absence indistinguishable from false, and false here means
            # "turn the cleanup job off" rather than "leave it alone".
            (Get-Command $CommandName).Parameters["OperationCleanupEnabled"].ParameterType.FullName | Should -Be "System.Management.Automation.SwitchParameter"
            (Get-Command $CommandName).Parameters["VersionCleanupEnabled"].ParameterType.FullName | Should -Be "System.Management.Automation.SwitchParameter"
        }

        It "Should accept only the four algorithms the catalog validates against" {
            $validateSet = (Get-Command $CommandName).Parameters["EncryptionAlgorithm"].Attributes | Where-Object { $PSItem -is [System.Management.Automation.ValidateSetAttribute] }
            $validateSet.ValidValues | Should -Be @("TRIPLE_DES_3KEY", "AES_128", "AES_192", "AES_256")
        }
    }

    Context "Values are settled before anything connects" {
        # These all refuse in BeginProcessing, so the unreachable instance name is never dialled.
        BeforeAll {
            $unreachableInstance = "dbatoolsci_nosuchhost_ssiscatalog"
        }

        It "Refuses a call that sets nothing" {
            { Set-DbaSsisCatalog -SqlInstance $unreachableInstance -EnableException } | Should -Throw "*at least one catalog property*"
        }

        It "Refuses a retention window outside the catalog's range" {
            { Set-DbaSsisCatalog -SqlInstance $unreachableInstance -RetentionWindow 3651 -EnableException } | Should -Throw "*between 1 and 3650 days*"
        }

        It "Refuses a project version count outside the catalog's range" {
            { Set-DbaSsisCatalog -SqlInstance $unreachableInstance -MaxProjectVersions 10000 -EnableException } | Should -Throw "*between 1 and 9999*"
        }

        It "Refuses a logging level the catalog does not accept" {
            # 100 is a sentinel meaning "use the customized level", not the top of a range, so 5
            # is refused while 100 is not.
            { Set-DbaSsisCatalog -SqlInstance $unreachableInstance -ServerLoggingLevel 5 -EnableException } | Should -Throw "*0, 1, 2, 3, 4 or 100*"
        }

        It "Refuses an execution mode the catalog does not accept" {
            { Set-DbaSsisCatalog -SqlInstance $unreachableInstance -DefaultExecutionMode 2 -EnableException } | Should -Throw "*0 (server) or 1 (Scale Out)*"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        $ssisInstance = $TestConfig.InstanceSsis

        function Get-SsisCatalogProperty {
            param($PropertyName)
            $splatPropertyRead = @{
                SqlInstance  = $TestConfig.InstanceSsis
                Database     = "SSISDB"
                Query        = "SELECT property_value FROM [catalog].[catalog_properties] WHERE property_name = @propertyName"
                SqlParameter = @{ propertyName = $PropertyName }
            }
            (Invoke-DbaQuery @splatPropertyRead).property_value
        }

        # The lab catalog is shared, so every property this suite touches is read first and put
        # back in AfterAll rather than reset to a value the suite decided was normal.
        $originalRetentionWindow = Get-SsisCatalogProperty -PropertyName "RETENTION_WINDOW"
        $originalMaxProjectVersions = Get-SsisCatalogProperty -PropertyName "MAX_PROJECT_VERSIONS"
        $originalOperationCleanup = Get-SsisCatalogProperty -PropertyName "OPERATION_CLEANUP_ENABLED"
        $originalVersionCleanup = Get-SsisCatalogProperty -PropertyName "VERSION_CLEANUP_ENABLED"
        $originalLoggingLevel = Get-SsisCatalogProperty -PropertyName "SERVER_LOGGING_LEVEL"
        $originalEncryptionAlgorithm = Get-SsisCatalogProperty -PropertyName "ENCRYPTION_ALGORITHM"
    }

    AfterAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        foreach ($restore in @(
                @("RETENTION_WINDOW", $originalRetentionWindow),
                @("MAX_PROJECT_VERSIONS", $originalMaxProjectVersions),
                @("OPERATION_CLEANUP_ENABLED", $originalOperationCleanup),
                @("VERSION_CLEANUP_ENABLED", $originalVersionCleanup),
                @("SERVER_LOGGING_LEVEL", $originalLoggingLevel)
            )) {
            $splatRestore = @{
                SqlInstance  = $TestConfig.InstanceSsis
                Database     = "SSISDB"
                Query        = "EXEC [catalog].[configure_catalog] @property_name = @propertyName, @property_value = @propertyValue;"
                SqlParameter = @{
                    propertyName  = $restore[0]
                    propertyValue = $restore[1]
                }
            }
            Invoke-DbaQuery @splatRestore
        }
    }

    Context "Setting properties" {
        It "Sets several properties in one call and returns the catalog" {
            $splatSet = @{
                SqlInstance        = $ssisInstance
                RetentionWindow    = 90
                MaxProjectVersions = 5
            }
            $configured = @(Set-DbaSsisCatalog @splatSet)
            $configured.Count | Should -Be 1
            $configured[0].RetentionWindow | Should -Be 90
            $configured[0].MaxProjectVersions | Should -Be 5

            Get-SsisCatalogProperty -PropertyName "RETENTION_WINDOW" | Should -Be 90
            Get-SsisCatalogProperty -PropertyName "MAX_PROJECT_VERSIONS" | Should -Be 5
        }

        It "Decorates the catalog exactly like the read command does" {
            $configured = @(Set-DbaSsisCatalog -SqlInstance $ssisInstance -RetentionWindow 91)[0]
            $read = @(Get-DbaSsisCatalog -SqlInstance $ssisInstance)[0]
            $configured.PSObject.TypeNames[0] | Should -Be "dbatools.SsisCatalog"
            Compare-Object -ReferenceObject $read.PSObject.Properties.Name -DifferenceObject $configured.PSObject.Properties.Name | Should -BeNullOrEmpty
            $configuredDisplaySet = $configured.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $readDisplaySet = $read.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $readDisplaySet -DifferenceObject $configuredDisplaySet | Should -BeNullOrEmpty
        }

        It "Sets a boolean property to false with the colon form" {
            $configured = @(Set-DbaSsisCatalog -SqlInstance $ssisInstance -OperationCleanupEnabled:$false)
            $configured.Count | Should -Be 1
            Get-SsisCatalogProperty -PropertyName "OPERATION_CLEANUP_ENABLED" | Should -Be "FALSE"
        }

        It "Leaves an unmentioned boolean property alone instead of setting it false" {
            # This is the leg the whole switch-through-Test-Bound rule exists for. The previous
            # test left OPERATION_CLEANUP_ENABLED false; a command reading switch truthiness would
            # now rewrite VERSION_CLEANUP_ENABLED to false too, and would leave the false one
            # false, so only the property that was true before catches it.
            Get-SsisCatalogProperty -PropertyName "VERSION_CLEANUP_ENABLED" | Should -Be "TRUE"
            $null = Set-DbaSsisCatalog -SqlInstance $ssisInstance -RetentionWindow 92
            Get-SsisCatalogProperty -PropertyName "VERSION_CLEANUP_ENABLED" | Should -Be "TRUE"
            Get-SsisCatalogProperty -PropertyName "OPERATION_CLEANUP_ENABLED" | Should -Be "FALSE"
        }

        It "Sets a boolean property back to true" {
            $null = Set-DbaSsisCatalog -SqlInstance $ssisInstance -OperationCleanupEnabled
            Get-SsisCatalogProperty -PropertyName "OPERATION_CLEANUP_ENABLED" | Should -Be "TRUE"
        }
    }

    Context "-WhatIf" {
        It "Reports without changing the catalog" {
            $before = Get-SsisCatalogProperty -PropertyName "RETENTION_WINDOW"
            $whatIfResult = @(Set-DbaSsisCatalog -SqlInstance $ssisInstance -RetentionWindow 123 -WhatIf)
            $whatIfResult.Count | Should -Be 0
            Get-SsisCatalogProperty -PropertyName "RETENTION_WINDOW" | Should -Be $before
        }
    }

    Context "-EncryptionAlgorithm" {
        It "Refuses while SSISDB is not in SINGLE_USER mode and does not re-encrypt" {
            # The catalog raises 27162 for this, and putting SSISDB into SINGLE_USER would
            # disconnect every other session on a shared instance - so the command checks the
            # precondition and says so rather than meeting it.
            $splatEncryption = @{
                SqlInstance         = $ssisInstance
                EncryptionAlgorithm = "AES_128"
                EnableException     = $false
                WarningVariable     = "encryptionWarnings"
                WarningAction       = "SilentlyContinue"
            }
            $refused = @(Set-DbaSsisCatalog @splatEncryption)
            $refused.Count | Should -Be 0
            ($encryptionWarnings -join " ") | Should -BeLike "*SINGLE_USER*"
            Get-SsisCatalogProperty -PropertyName "ENCRYPTION_ALGORITHM" | Should -Be $originalEncryptionAlgorithm
        }
    }

    Context "An instance with no SSIS catalog" {
        # InstanceSingle carries no SSISDB, so this exercises the presence check rather than
        # failing inside the catalog schema.
        It "Warns and returns nothing" {
            $splatNoCatalog = @{
                SqlInstance     = $TestConfig.InstanceSingle
                RetentionWindow = 30
                EnableException = $false
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $none = @(Set-DbaSsisCatalog @splatNoCatalog)
            $none.Count | Should -Be 0
            ($warn -join " ") | Should -BeLike "*No SSIS catalog (SSISDB) found*"
        }

        It "Throws under -EnableException" {
            { Set-DbaSsisCatalog -SqlInstance $TestConfig.InstanceSingle -RetentionWindow 30 -EnableException } | Should -Throw "*No SSIS catalog (SSISDB) found*"
        }
    }
}
