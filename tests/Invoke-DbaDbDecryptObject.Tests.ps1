param($ModuleName = 'dbatools')

Describe "Invoke-DbaDbDecryptObject Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        # Setup code (if any) goes here
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandName = 'Invoke-DbaDbDecryptObject'
            $ParameterFilter = {-not $PSItem.IsInherited}
            $command = Get-Command -Name $CommandName
        }
        It "Should have SqlInstance parameter" {
            $command | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential parameter" {
            $command | Should -HaveParameter SqlCredential
        }
        It "Should have Database parameter" {
            $command | Should -HaveParameter Database
        }
        It "Should have ObjectName parameter" {
            $command | Should -HaveParameter ObjectName
        }
        It "Should have EncodingType parameter" {
            $command | Should -HaveParameter EncodingType
        }
        It "Should have ExportDestination parameter" {
            $command | Should -HaveParameter ExportDestination
        }
        It "Should have EnableException parameter" {
            $command | Should -HaveParameter EnableException
        }
    }
}

Describe "Invoke-DbaDbDecryptObject Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $dbname = "dbatoolsci_decrypt_$random"
        $PSDefaultParameterValues = @{
            "It:Skip" = $true # Skip all tests by default
        }

        # Remove the database if it exists
        Remove-DbaDatabase -SqlInstance $global:instance1 -Database $dbname -Confirm:$false

        # Create the database
        $db = New-DbaDatabase -SqlInstance $global:instance1 -Name $dbname

        if ($null -ne $global:instance2SQLUserName) {
            $instance2SecurePassword = ConvertTo-SecureString -String $global:instance2SQLPassword -AsPlainText -Force
            $instance2SqlCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $global:instance2SQLUserName, $instance2SecurePassword
        }

        Remove-DbaDatabase -SqlInstance $global:instance2 -SqlCredential $instance2SqlCredential -Database $dbname -Confirm:$false
        $instance2Db = New-DbaDatabase -SqlInstance $global:instance2 -SqlCredential $instance2SqlCredential -Name $dbname

        # test object for usage with sql credential
        $remoteDacSampleEncryptedView = "CREATE VIEW dbo.dbatoolsci_test_remote_dac_vw WITH ENCRYPTION AS SELECT 'remoteDac' as TestFeature;"
        $instance2Db.Query($remoteDacSampleEncryptedView)

        # Setup the code for the encrypted function
        $queryScalarFunction = @"
-- =============================================
-- Author:        Sander Stad
-- Description:   Dummy encrypted scalar function to test the command
-- =============================================
CREATE FUNCTION dbo.DummyEncryptedScalarFunction
(
    @param1 varchar(100)
)
RETURNS VARCHAR
WITH ENCRYPTION
AS
BEGIN
    -- Declare the return variable here
    DECLARE @ResultVar VARCHAR(100)

    -- Add the T-SQL statements to compute the return value here
    SELECT @ResultVar = 'Hello this is a test function' + @param1

    -- Return the result of the function
    RETURN @ResultVar

END
"@
        # Create the encrypted scalar function
        $db.Query($queryScalarFunction)

        # Setup the code for the encrypted inline function
        $queryInlineTVF = @"
CREATE FUNCTION dbo.DummyEncryptedInlineTVF
(
    @Id INTEGER
)
RETURNS TABLE
WITH ENCRYPTION
AS
    RETURN SELECT @@SERVERNAME AS ServerName, @@VERSION AS Version, @Id AS Id;
"@
        # Create the encrypted inline TVF
        $db.Query($queryInlineTVF)

        # Setup the code for the encrypted table valued function
        $queryTableValuedFunction = @"
CREATE FUNCTION dbo.DummyEncryptedTableValuedFunction
(
    @Id INTEGER
)
RETURNS @r TABLE(i INTEGER)
WITH ENCRYPTION
AS
BEGIN
    INSERT INTO @r (i) VALUES (@Id)
    RETURN
END;
"@
        # Create the encrypted table valued function
        $db.Query($queryTableValuedFunction)

        # Setup the query for the encrypted stored procedure
        $queryStoredProcedure = @"
-- =============================================
-- Author:        Sander Stad
-- Description:   Dummy encrypted stored procedure to test the command
-- =============================================
CREATE PROCEDURE dbo.DummyEncryptedStoredProcedure
    @param1 VARCHAR(100)
WITH ENCRYPTION
AS
BEGIN
    -- SET NOCOUNT ON added to prevent extra result sets from
    -- interfering with SELECT statements.
    SET NOCOUNT ON;

    -- Insert statements for procedure here
    SELECT @param1
END
"@

        # Create the encrypted stored procedure
        $db.Query($queryStoredProcedure)

        # Setup the code for the encrypted view
        $setupView = @"
CREATE VIEW dbo.dbatoolsci_test_vw
WITH ENCRYPTION
AS
SELECT 1 AS Id;
"@
        # Create the encrypted view
        $db.Query($setupView)

        # Create a schema to test with
        $db.Query("CREATE SCHEMA dbatools")

        # Setup the code for the encrypted trigger
        $setupTable = @"
CREATE TABLE dbatools.dbatoolsci_tab1
(
    Id INTEGER
);
"@
        $db.Query($setupTable)

        $setupTrigger = @"
CREATE TRIGGER dbatools.dbatoolsci_test_trigger
ON dbatools.dbatoolsci_tab1
WITH ENCRYPTION
INSTEAD OF DELETE
AS
BEGIN
    RAISERROR ('Invoke-DbaDbDecryptObject.Tests', 16, 10);
END;
"@
        # Create the encrypted trigger
        $db.Query($setupTrigger)

        # Setup the code for an encrypted view in a schema other than dbo
        $setupViewInSchema = @"
CREATE VIEW dbatools.dbatoolsci_test_schema_vw
WITH ENCRYPTION
AS
SELECT 'dbatools' as SchemaName;
"@
        # Create the encrypted view
        $db.Query($setupViewInSchema)

        # Create another schema to test with
        $db.Query("CREATE SCHEMA dbatools2")

        # Setup the code for an encrypted view in another schema other than dbo
        $setupAnotherViewInSchema = @"
CREATE VIEW dbatools2.dbatoolsci_test_schema_vw
WITH ENCRYPTION
AS
SELECT 'dbatools2' as SchemaName;
"@
        # Create the encrypted view
        $db.Query($setupAnotherViewInSchema)

        # Setup the code for a view that has UTF8 characters
        $setupViewWithUTF8 = @"
CREATE VIEW dbo.dbatoolsci_test_UTF8_vw
WITH ENCRYPTION
AS
SELECT 'áéíñóú¡¿' as SampleUTF8;
"@
        # Create the encrypted view
        $db.Query($setupViewWithUTF8)

        # Check if DAC is enabled
        $config = Get-DbaSpConfigure -SqlInstance $global:instance1 -ConfigName RemoteDacConnectionsEnabled
        if ($config.ConfiguredValue -ne 1) {
            Set-DbaSpConfigure -SqlInstance $global:instance1 -ConfigName RemoteDacConnectionsEnabled -Value $true
        }

        $instance2Config = Get-DbaSpConfigure -SqlInstance $global:instance2 -SqlCredential $instance2SqlCredential -ConfigName RemoteDacConnectionsEnabled
        if ($instance2Config.ConfiguredValue -ne 1) {
            Set-DbaSpConfigure -SqlInstance $global:instance2 -SqlCredential $instance2SqlCredential -ConfigName RemoteDacConnectionsEnabled -Value $true
        }
    }

    AfterAll {
        # Remove the database if it exists
        Remove-DbaDatabase -SqlInstance $global:instance1 -Database $dbname -Confirm:$false
        Remove-DbaDatabase -SqlInstance $global:instance2 -SqlCredential $instance2SqlCredential -Database $dbname -Confirm:$false

        # Set the original configuration
        Set-DbaSpConfigure -SqlInstance $global:instance1 -ConfigName RemoteDacConnectionsEnabled -Value $config.ConfiguredValue -WarningAction SilentlyContinue
        Set-DbaSpConfigure -SqlInstance $global:instance2 -SqlCredential $instance2SqlCredential -ConfigName RemoteDacConnectionsEnabled -Value $instance2Config.ConfiguredValue -WarningAction SilentlyContinue
    }

    Context "DAC enabled" {
        It "Should throw error" {
            Set-DbaSpConfigure -SqlInstance $global:instance1 -Name RemoteDacConnectionsEnabled -Value $false
            { Invoke-DbaDbDecryptObject -SqlInstance $global:instance1 -Database $dbname -ObjectName DummyEncryptedStoredProcedure -WarningAction SilentlyContinue -ErrorAction Stop } | Should -Throw -ExpectedMessage "*DAC is not enabled for instance*"
            Set-DbaSpConfigure -SqlInstance $global:instance1 -Name RemoteDacConnectionsEnabled -Value $true -WarningAction SilentlyContinue
        }
    }

    Context "Decrypt Scalar Function" {
        It "Should be successful" {
            $result = Invoke-DbaDbDecryptObject -SqlInstance $global:instance1 -Database $dbname -ObjectName DummyEncryptedScalarFunction
            $result.Script | Should -Be $queryScalarFunction
        }
    }

    Context "Decrypt Inline TVF" {
        It "Should be successful" {
            $result = Invoke-DbaDbDecryptObject -SqlInstance $global:instance1 -Database $dbname -ObjectName DummyEncryptedInlineTVF
            $result.Script | Should -Be $queryInlineTVF
        }
    }

    Context "Decrypt TVF" {
        It "Should be successful" {
            $result = Invoke-DbaDbDecryptObject -SqlInstance $global:instance1 -Database $dbname -ObjectName DummyEncryptedTableValuedFunction
            $result.Script | Should -Be $queryTableValuedFunction
        }
    }

    Context "Decrypt Stored Procedure" {
        It "Should be successful" {
            $result = Invoke-DbaDbDecryptObject -SqlInstance $global:instance1 -Database $dbname -ObjectName DummyEncryptedStoredProcedure
            $result.Script | Should -Be $queryStoredProcedure
        }
    }

    Context "Decrypt view" {
        It "Should be successful" {
            $result = Invoke-DbaDbDecryptObject -SqlInstance $global:instance1 -Database $dbname -ObjectName dbatoolsci_test_vw
            $result.Script | Should -Be $setupView
        }
    }

    Context "Decrypt trigger in a schema other than dbo" {
        It "Should be successful" {
            $result = Invoke-DbaDbDecryptObject -SqlInstance $global:instance1 -Database $dbname -ObjectName dbatoolsci_test_trigger
            $result.Script | Should -Be $setupTrigger
        }
    }

    Context "Decrypt objects with the same name but in different schemas" {
        It "Should be successful" {
            @(Invoke-DbaDbDecryptObject -SqlInstance $global:instance1 -Database $dbname -ObjectName dbatoolsci_test_schema_vw).Count | Should -Be 2
        }
    }

    Context "Decrypt view with UTF8" {
        It "Should be successful" {
            $result = Invoke-DbaDbDecryptObject -SqlInstance $global:instance1 -Database $dbname -ObjectName dbatoolsci_test_UTF8_vw -EncodingType UTF8
            $result.Script | Should -Not -BeNullOrEmpty
        }
    }

    Context "Decrypt view and use a destination folder" {
        It "Should be successful" {
            $result = Invoke-DbaDbDecryptObject -SqlInstance $global:instance1 -Database $dbname -ObjectName dbatoolsci_test_vw -ExportDestination .
            (Get-Content $result.OutputFile | Out-String).Trim() | Should -Be $setupView.Trim()
            Remove-Item $result.OutputFile
        }
    }

    Context "Decrypt all encrypted objects and use a destination folder" {
        It "Should be successful" {
            $result = Invoke-DbaDbDecryptObject -SqlInstance $global:instance1 -Database $dbname -ExportDestination .
            @($result | Where-Object { $_.Type -eq 'StoredProcedure' }).Count       | Should -Be 1
            @($result | Where-Object { $_.Type -eq 'Trigger' }).Count               | Should -Be 1
            @($result | Where-Object { $_.Type -eq 'UserDefinedFunction' }).Count   | Should -Be 3
            @($result | Where-Object { $_.Type -eq 'View' }).Count                  | Should -Be 4
        }
    }

    Context "Connect to an instance (ideally a remote instance) using a SqlCredential and decrypt an object" {
        It "Should be successful" {
            $result = Invoke-DbaDbDecryptObject -SqlInstance $global:instance2 -SqlCredential $instance2SqlCredential -Database $dbname -ObjectName dbatoolsci_test_remote_dac_vw -ExportDestination .
            (Get-Content $result.OutputFile | Out-String).Trim() | Should -Be $remoteDacSampleEncryptedView.Trim()
            Remove-Item $result.OutputFile
        }
    }
}
