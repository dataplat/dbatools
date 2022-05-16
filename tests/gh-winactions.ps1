Describe "Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $PSDefaultParameterValues["*:SqlInstance"] = "(localdb)\MSSQLLocalDB"
        $PSDefaultParameterValues["*:Confirm"] = $false
        #$PSDefaultParameterValues["*:WarningAction"] = "SilentlyContinue"
        $global:ProgressPreference = "SilentlyContinue"

        Import-Module ./dbatools.psm1 -Force
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

    It "connects to Azure" {
        $PSDefaultParameterValues.Clear()
        $securestring = ConvertTo-SecureString $env:CLIENTSECRET -AsPlainText -Force
        $azurecred = New-Object PSCredential -ArgumentList $env:CLIENTID, $securestring
        Connect-DbaInstance -SqlInstance dbatoolstest.database.windows.net -SqlCredential $azurecred -Tenant $env:TENANTID | Select-Object -ExpandProperty ComputerName | Should -Be "dbatoolstest.database.windows.net"
        Connect-DbaInstance -SqlInstance "Server=dbatoolstest.database.windows.net; Authentication=Active Directory Service Principal; Database=test; User Id=$env:CLIENTID; Password=$env:CLIENTSECRET;" | Select-Object -ExpandProperty ComputerName | Should -Be "dbatoolstest.database.windows.net"
    }

    It -Skip "gets a database from Azure" {
        $PSDefaultParameterValues.Clear()
        $securestring = ConvertTo-SecureString $env:CLIENTSECRET -AsPlainText -Force
        $azurecred = New-Object PSCredential -ArgumentList $env:CLIENTID, $securestring
        $server = Connect-DbaInstance -SqlInstance dbatoolstest.database.windows.net -SqlCredential $azurecred -Tenant $env:TENANTID
        (Get-DbaDatabase -SqlInstance $server -Database test).Name | Should -Be "test"
    }
}
