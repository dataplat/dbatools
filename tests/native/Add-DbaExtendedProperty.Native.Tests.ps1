#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Add-DbaExtendedProperty",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Add-DbaExtendedProperty Azure" -Tag IntegrationTests {
    It "stores a property in Azure SQL Database" -Tag "NativeChecklist:azure-sqldb" {
        $splatAzureConnection = @{
            SqlInstance = $TestConfig.AzureSqlDbServer
            Database = $TestConfig.AzureSqlDbName
            SqlCredential = $TestConfig.AzureSqlDbCred
            EnableException = $true
        }
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -in @(40613, -2) -or $azureError -is [System.TimeoutException]) { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly 'SqlDatabase'
        $azureDatabase = $azureServer.Databases[$TestConfig.AzureSqlDbName]
        $azurePropertyName = "native_property_$([guid]::NewGuid().ToString('N'))"
        try {
            $azureProperty = Add-DbaExtendedProperty -InputObject $azureDatabase -Name $azurePropertyName -Value 'Azure property value' -Confirm:$false -EnableException
            $azureProperty.Name | Should -BeExactly $azurePropertyName
            $azureStored = $azureDatabase.ExecuteWithResults("SELECT value FROM sys.extended_properties WHERE class = 0 AND name = N'$azurePropertyName';")
            $azureStored.Tables[0].Rows.Count | Should -Be 1
            $azureStored.Tables[0].Rows[0].value | Should -BeExactly 'Azure property value'
        } finally {
            $azureDatabase.ExtendedProperties.Refresh()
            if ($azureDatabase.ExtendedProperties.Contains($azurePropertyName)) {
                $azureDatabase.ExtendedProperties[$azurePropertyName].Drop()
            }
        }
    }
}

Describe "Native Add-DbaExtendedProperty SQL authentication" -Tag IntegrationTests, "NativeChecklist:sql-login" {
    BeforeAll {
        $loginServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSqlLogin -SqlCredential $TestConfig.SqlLoginCred -EnableException
        $loginDbName = "dbatoolsci_property_login_$([guid]::NewGuid().ToString('N'))"
        $loginDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $loginServer, $loginDbName
        $loginDatabase.Create()
    }

    AfterAll {
        if ($loginServer -and $loginDatabase -and $loginDatabase.State -eq 'Existing') {
            $loginServer.KillDatabase($loginDbName)
        }
    }

    It "stores a property with the SQL credential" {
        $splatLoginProperty = @{
            SqlInstance = $TestConfig.InstanceSqlLogin
            SqlCredential = $TestConfig.SqlLoginCred
            Database = $loginDbName
            Name = 'native_login_property'
            Value = 'SQL login property value'
            Confirm = $false
            EnableException = $true
        }
        $loginProperty = Add-DbaExtendedProperty @splatLoginProperty
        $loginProperty.Name | Should -BeExactly 'native_login_property'
        $loginStored = $loginDatabase.ExecuteWithResults("SELECT value FROM sys.extended_properties WHERE class = 0 AND name = N'native_login_property';")
        $loginStored.Tables[0].Rows.Count | Should -Be 1
        $loginStored.Tables[0].Rows[0].value | Should -BeExactly 'SQL login property value'
    }

    It "warns without output when the SQL credential is omitted" {
        $loginWarnings = @()
        $splatLoginDenied = @{
            SqlInstance = $TestConfig.InstanceSqlLogin
            Database = $loginDbName
            Name = 'native_denied_property'
            Value = 'must not be stored'
            Confirm = $false
            EnableException = $false
            WarningAction = 'SilentlyContinue'
            WarningVariable = 'loginWarnings'
        }
        @(Add-DbaExtendedProperty @splatLoginDenied).Count | Should -Be 0
        $loginWarnings | Should -Not -BeNullOrEmpty
    }

    It "warns without output with EnableException when the SQL credential is omitted" {
        # Pinned public/Add-DbaExtendedProperty.ps1:140 calls Get-DbaDatabase without forwarding EnableException.
        $loginWarnings = @()
        $splatLoginDenied = @{
            SqlInstance = $TestConfig.InstanceSqlLogin
            Database = $loginDbName
            Name = "native_denied_property"
            Value = "denied"
            Confirm = $false
            EnableException = $true
            WarningAction = "SilentlyContinue"
            WarningVariable = "loginWarnings"
        }
        @(Add-DbaExtendedProperty @splatLoginDenied).Count | Should -Be 0
        $loginWarnings | Should -Not -BeNullOrEmpty
    }
}

Describe "Native Add-DbaExtendedProperty server identity regression" -Tag IntegrationTests {
    BeforeAll {
        $nativePropertyServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativePropertyDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativePropertyServer, "dbatoolsci_native_property_$(Get-Random)"
        $nativePropertyDatabase.Create()
    }

    AfterAll {
        if ($nativePropertyDatabase) {
            $nativePropertyServer.KillDatabase($nativePropertyDatabase.Name)
        }
    }

    It "selects databases using the documented wildcard parameter" {
        $splatNativeProperty = @{
            SqlInstance     = $nativePropertyServer
            Database        = "$($nativePropertyDatabase.Name)*"
            Name            = "native_database_wildcard"
            Value           = "documented pattern"
            Confirm         = $false
            EnableException = $true
        }
        $nativeProperties = @(Add-DbaExtendedProperty @splatNativeProperty)
        $nativeProperties.Count | Should -Be 1
        $nativeProperties[0].ParentName | Should -BeExactly $nativePropertyDatabase.Name
    }

    It "creates and returns typed properties on multiple SMO pipeline objects" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:switch-false" {
        $nativePropertyDatabase.ExecuteNonQuery("CREATE TABLE dbo.native_property_one (id int); CREATE TABLE dbo.native_property_two (id int);")
        $nativePropertyDatabase.Tables.Refresh()
        $nativePropertyTables = @($nativePropertyDatabase.Tables["native_property_one", "dbo"], $nativePropertyDatabase.Tables["native_property_two", "dbo"])
        $splatNativeProperty = @{
            Name            = "native_'quoted]property"
            Value           = "value with 'quotes' and ] brackets"
            Confirm         = $false
            WhatIf          = $false
            EnableException = $true
        }
        $nativeProperties = @($nativePropertyTables | Add-DbaExtendedProperty @splatNativeProperty)
        $nativeProperties.Count | Should -Be 2
        foreach ($nativeProperty in $nativeProperties) {
            $nativeProperty | Should -BeOfType Microsoft.SqlServer.Management.Smo.ExtendedProperty
            $nativeProperty.Name | Should -BeExactly $splatNativeProperty.Name
            $nativeProperty.Value | Should -BeExactly $splatNativeProperty.Value
            $nativeProperty.Type | Should -BeExactly "Table"
            $nativeProperty.Server | Should -BeOfType Microsoft.SqlServer.Management.Smo.Server
            ($nativeProperty.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly "ComputerName,InstanceName,SqlInstance,ParentName,Type,Name,Value"
        }
    }

    It "does not create an extended property under WhatIf" -Tag "NativeChecklist:whatif-confirm" {
        $splatNativeProperty = @{
            InputObject     = $nativePropertyDatabase
            Name            = "native_property_whatif"
            Value           = "not stored"
            Confirm         = $false
            WhatIf          = $true
            EnableException = $true
        }
        @(Add-DbaExtendedProperty @splatNativeProperty).Count | Should -Be 0
        $nativePropertyDatabase.ExtendedProperties.Refresh()
        $nativePropertyDatabase.ExtendedProperties.Contains("native_property_whatif") | Should -BeFalse
    }

    It "warns for duplicate properties or throws with EnableException" -Tag "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $splatNativeProperty = @{
            InputObject     = $nativePropertyDatabase
            Name            = "native_property_duplicate"
            Value           = "original"
            Confirm         = $false
            EnableException = $true
        }
        $null = Add-DbaExtendedProperty @splatNativeProperty
        $splatNativeProperty.EnableException = $false
        $splatNativeProperty.WarningAction = "SilentlyContinue"
        $splatNativeProperty.WarningVariable = "nativePropertyWarnings"
        @(Add-DbaExtendedProperty @splatNativeProperty).Count | Should -Be 0
        ($nativePropertyWarnings -join " ") | Should -BeLike "*Failed to add extended property native_property_duplicate*"
        $splatNativeProperty.EnableException = $true
        { Add-DbaExtendedProperty @splatNativeProperty } | Should -Throw
        $nativePropertyDatabase.ExtendedProperties["native_property_duplicate"].Value | Should -BeExactly "original"
    }

    It "retains database input from successful instances after a failed connection" -Tag "NativeChecklist:multi-instance-failure" {
        $splatNativeProperty = @{
            SqlInstance     = @("tcp:127.0.0.1,1", $nativePropertyServer)
            Database        = $nativePropertyDatabase.Name
            Name            = "native_property_connection"
            Value           = "success after failure"
            Confirm         = $false
            EnableException = $false
            WarningAction   = "SilentlyContinue"
            WarningVariable = "nativePropertyWarnings"
        }
        $nativeProperties = @(Add-DbaExtendedProperty @splatNativeProperty)
        $nativeProperties.Count | Should -Be 1
        $nativeProperties[0].ParentName | Should -BeExactly $nativePropertyDatabase.Name
        ($nativePropertyWarnings -join " ") | Should -BeLike "*Failure*"
    }

    It "reports the actual owning server when the input already carries instance metadata" {
        $nativePropertyDatabase | Add-Member -NotePropertyName ComputerName -NotePropertyValue "metadata-computer" -Force
        $nativePropertyDatabase | Add-Member -NotePropertyName InstanceName -NotePropertyValue "metadata-instance" -Force
        $nativePropertyDatabase | Add-Member -NotePropertyName SqlInstance -NotePropertyValue "metadata-sql" -Force
        $nativePropertyOldServer = Get-Variable -Name server -Scope Global -ErrorAction SilentlyContinue
        $nativePropertyOldServerValue = if ($nativePropertyOldServer) { $nativePropertyOldServer.Value } else { $null }
        try {
            $global:server = "unrelated-caller-value"
            $splatNativeProperty = @{
                InputObject     = $nativePropertyDatabase
                Name            = "native_server_identity"
                Value           = "correct owner"
                Confirm         = $false
                EnableException = $true
            }
            $nativeProperty = Add-DbaExtendedProperty @splatNativeProperty
            $nativeProperty.Server | Should -BeOfType Microsoft.SqlServer.Management.Smo.Server
            [object]::ReferenceEquals($nativeProperty.Server, $nativePropertyServer) | Should -BeTrue
            $nativeProperty.ComputerName | Should -BeExactly "metadata-computer"
            $nativeProperty.InstanceName | Should -BeExactly "metadata-instance"
            $nativeProperty.SqlInstance | Should -BeExactly "metadata-sql"
        } finally {
            if ($nativePropertyOldServer) {
                Set-Variable -Name server -Scope Global -Value $nativePropertyOldServerValue
            } else {
                Remove-Variable -Name server -Scope Global -ErrorAction SilentlyContinue
            }
        }
    }
}
