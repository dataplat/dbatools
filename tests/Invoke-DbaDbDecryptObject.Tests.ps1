$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ObjectName', 'EncodingType', 'ExportDestination', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "UnitTests" {
    BeforeAll {
        # Get a random value for the database name
        $random = Get-Random

        # Setup the database name
        $dbname = "dbatoolsci_decrypt_$random"

        # Remove the database if it exists
        Remove-DbaDatabase -SqlInstance $script:instance1 -Database $dbname -Confirm:$false

        # Create the database
        $db = New-DbaDatabase -SqlInstance $script:instance1 -Name $dbname

        # Setup the code for the encrypted function
        $queryFunction = "
-- =============================================
-- Author:        Sander Stad
-- Description:   Dummy encrypted function to test the command
-- =============================================
CREATE FUNCTION DummyEncryptedFunction
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
        "
        # Create the encrypted function
        $db.Query($queryFunction)

        # Setup the query for the encrypted stored procedure
        $queryStoredProcedure = "
-- =============================================
-- Author:        Sander Stad
-- Description:   Dummy encrypted stored procedure to test the command
-- =============================================
CREATE PROCEDURE DummyEncryptedFunctionStoredProcedure
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
        "

        # Create the encrypted stored procedure
        $db.Query($queryStoredProcedure)

        # Check if DAC is enabled
        $config = Get-DbaSpConfigure -SqlInstance $script:instance1 -ConfigName RemoteDacConnectionsEnabled
        if ($config.ConfiguredValue -ne 1) {
            Set-DbaSpConfigure -SqlInstance $script:instance1 -ConfigName RemoteDacConnectionsEnabled -Value $true
        }
    }

    AfterAll {
        # Remove the database if it exists
        Remove-DbaDatabase -SqlInstance $script:instance1 -Database $dbname -Confirm:$false

        # Set the original configuration
        Set-DbaSpConfigure -SqlInstance $script:instance1 -ConfigName RemoteDacConnectionsEnabled -Value $config.ConfiguredValue -WarningAction SilentlyContinue
    }

    Context "DAC enabled" {
        # too much messing around punts appveyor
        It -Skip "Should throw error" {
            Set-DbaSpConfigure -SqlInstance $script:instance1 -Name RemoteDacConnectionsEnabled -Value $false
            Invoke-DbaDbDecryptObject -SqlInstance $script:instance1 -Database $dbname -ObjectName DummyEncryptedFunctionStoredProcedure -WarningVariable warn -WarningAction SilentlyContinue
            $error[0].Exception | Should -BeLike "*DAC is not enabled for instance*"
            Set-DbaSpConfigure -SqlInstance $script:instance1 -Name RemoteDacConnectionsEnabled -Value $true -WarningAction SilentlyContinue
        }
    }

    Context "Decrypt Function" {
        It -Skip "Should be successful" {
            $result = Invoke-DbaDbDecryptObject -SqlInstance $script:instance1 -Database $dbname -ObjectName DummyEncryptedFunction
            $result.Script | Should -Be $queryFunction

        }
    }

    Context "Decrypt Stored Procedure" {
        It -Skip "Should be successful" {
            $result = Invoke-DbaDbDecryptObject -SqlInstance $script:instance1 -Database $dbname -ObjectName DummyEncryptedFunctionStoredProcedure
            $result.Script | Should -Be $queryStoredProcedure

        }
    }
}