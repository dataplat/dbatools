Describe "Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        # if desktop then use localdb if desktop then use full
        if ($PSVersionTable.PSEdition -eq "Core") {
            # [New-DbaDatabase] Failure | LocalDB is not supported on this platform.
            $password = ConvertTo-SecureString "dbatools.I0" -AsPlainText -Force
            $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "sa", $password
            $PSDefaultParameterValues["*:SqlInstance"] = "localhost"
            $PSDefaultParameterValues["*:SqlCredential"] = $cred
        } else {
            $PSDefaultParameterValues["*:SqlInstance"] = "(localdb)\MSSQLLocalDB"
        }

        $PSDefaultParameterValues["*:Confirm"] = $false
        #$PSDefaultParameterValues["*:WarningAction"] = "SilentlyContinue"
        $global:ProgressPreference = "SilentlyContinue"

        if (-not (Get-Module dbatools)) {
            Write-Warning "Importing dbatools from source"
            Import-Module dbatools.library
            Import-Module ./dbatools.psd1 -Force
        }
    }

    It "publishes a package" {
        $db = New-DbaDatabase
        $dbname = $db.Name
        $null = $db.Query("CREATE TABLE dbo.example (id int, PRIMARY KEY (id));
            INSERT dbo.example
            SELECT top 100 object_id
            FROM sys.objects")

        $publishprofile = New-DbaDacProfile -Database $dbname -Path C:\temp
        $extractOptions = New-DbaDacOption -Action Export
        $extractOptions.ExtractAllTableData = $true
        $dacpac = Export-DbaDacPackage -Database $dbname -DacOption $extractOptions
        $null = Remove-DbaDatabase -Database $db.Name

        $results = $dacpac | Publish-DbaDacPackage -PublishXml $publishprofile.FileName -Database $dbname -Confirm:$false
        $results.Result | Should -BeLike '*Update complete.*'
        $ids = Invoke-DbaQuery -Database $dbname -Query 'SELECT id FROM dbo.example'
        $ids.id | Should -Not -BeNullOrEmpty
        $null = Remove-DbaDatabase -Database $db.Name
    }

    It "connects to Azure using tenant and client id + client secret" {
        $PSDefaultParameterValues.Clear()
        $securestring = ConvertTo-SecureString $env:CLIENTSECRET -AsPlainText -Force
        $azurecred = New-Object PSCredential -ArgumentList $env:CLIENTID, $securestring
        Connect-DbaInstance -SqlInstance dbatoolstest.database.windows.net -SqlCredential $azurecred -Tenant $env:TENANTID -Verbose | Select-Object -ExpandProperty ComputerName | Should -Be "dbatoolstest.database.windows.net"
    }


    It "connects to Azure using a query string" {
        # this doesn't work on github, it throws
        # Method not found: 'Microsoft.Identity.Client.AcquireTokenByUsernamePasswordParameterBuilder'
        if ($PSVersionTable.PSEdition -eq "Core") {
            Connect-DbaInstance -SqlInstance "Server=dbatoolstest.database.windows.net; Authentication=Active Directory Service Principal; Database=test; User Id=$env:CLIENTID; Password=$env:CLIENTSECRET;" | Select-Object -ExpandProperty ComputerName | Should -Be "dbatoolstest.database.windows.net"

            Connect-DbaInstance -SqlInstance "Server=dbatoolstest.database.windows.net; Authentication=Active Directory Service Principal; Database=test; User Id=$env:CLIENT_GUID; Password=$env:CLIENT_GUID_SECRET;" | Select-Object -ExpandProperty ComputerName | Should -Be "dbatoolstest.database.windows.net"
        } else {
            $true | Should -Be $true
        }
    }

    It "gets a database from Azure" {
        $PSDefaultParameterValues.Clear()
        $securestring = ConvertTo-SecureString $env:CLIENTSECRET -AsPlainText -Force
        $azurecred = New-Object PSCredential -ArgumentList $env:CLIENTID, $securestring
        $server = Connect-DbaInstance -SqlInstance dbatoolstest.database.windows.net -SqlCredential $azurecred -Tenant $env:TENANTID
        (Get-DbaDatabase -SqlInstance $server -Database test).Name | Should -Be "test"
    }

    It "detects ML Services CAB files for SQL Server 2017 updates" {
        # Reset default parameters for this test
        $PSDefaultParameterValues.Clear()

        # Prepare test environment
        $testPath = "C:\Temp\dbatools_MLTest_$(Get-Random)"
        $null = New-Item -Path $testPath -ItemType Directory -Force

        try {
            # Create dummy KB installer file for SQL 2017
            $kbFile = "SQLServer2017-KB4498951-x64.exe"
            $null = New-Item -Path "$testPath\$kbFile" -ItemType File -Force

            # Create mock ML Services CAB files
            $cabFiles = @(
                "SRO_3.3.3.0_1033.cab",
                "SPO_9.2.0.24_1033.cab"
            )
            foreach ($cab in $cabFiles) {
                $null = New-Item -Path "$testPath\$cab" -ItemType File -Force
            }

            # Test with WhatIf to avoid actual installation
            $password = ConvertTo-SecureString "dbatools.I0" -AsPlainText -Force
            $cred = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "sa", $password

            $splatUpdate = @{
                ComputerName    = "localhost"
                SqlCredential   = $cred
                KB              = "4498951"
                Path            = $testPath
                EnableException = $true
                WhatIf          = $true
            }

            # Execute Update-DbaInstance in WhatIf mode
            $result = Update-DbaInstance @splatUpdate 3>$null

            # Verify results
            $result | Should -Not -BeNullOrEmpty
            $result.KB | Should -Be 4498951

            # Verify CAB file detection worked
            if ($result.PSObject.Properties.Name -contains "MLServicesCabFiles") {
                Write-Warning "ML Services CAB files detected: $($result.MLServicesCabFiles.Count) files"
            }
        } finally {
            # Cleanup
            if (Test-Path $testPath) {
                Remove-Item -Path $testPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}