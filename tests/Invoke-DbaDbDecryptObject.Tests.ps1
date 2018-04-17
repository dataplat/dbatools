$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Unit Tests" -Tags "UnitTests" {

    BeforeAll {
        # Get a random value for the database name
        $random = Get-Random

        # Setup the database name
        $dbname = "dbatoolsci_decrypt_$random"

        # Remove the database if it exists
        Remove-DbaDatabase -SqlInstance $script:instance1 -Database $dbname -Confirm:$false

        # Get a server object
        $server = Connect-DbaInstance -SqlInstance $script:instance1

        # Create the database
        $server = Connect-DbaInstance -SqlInstance $script:instance1
        $server.Query("CREATE DATABASE $dbname;")

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
        $server.Databases[$dbname].Query($queryFunction)

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
        $server.Databases[$dbname].Query($queryStoredProcedure)

        # Check if DAC is enabled
        $config = Get-DbaSpConfigure -SqlInstance $script:instance1 -ConfigName RemoteDacConnectionsEnabled
        if ($config.ConfiguredValue -ne 1) {
            Set-DbaSpConfigure -SqlInstance $script:instance1 -ConfigName RemoteDacConnectionsEnabled -Value 1
        }
    }

    AfterAll {
        # Remove the database if it exists
        Remove-DbaDatabase -SqlInstance $script:instance1 -Database $dbname -Confirm:$false

        # Set the original configuration
        Set-DbaSpConfigure -SqlInstance $script:instance1 -ConfigName RemoteDacConnectionsEnabled -Value $config.ConfiguredValue
    }

    Context "DAC enabled" {
        Set-DbaSpConfigure -SqlInstance $script:instance1 -ConfigName RemoteDacConnectionsEnabled -Value 0

        It "Should throw error" {
                Invoke-DbaDbDecryptObject -SqlInstance $script:instance1 -Database $dbname -ObjectName DummyEncryptedFunctionStoredProcedure
                $error[0].Exception | Should -BeLike "*DAC is not enabled for instance*"
        }

        Set-DbaSpConfigure -SqlInstance $script:instance1 -ConfigName RemoteDacConnectionsEnabled -Value 1
    }

    Context "Decrypt Function" {
        It "Should be successful" {
            $result = Invoke-DbaDbDecryptObject -SqlInstance $script:instance1 -Database $dbname -ObjectName DummyEncryptedFunction
            $result
            $result.Script | Should Be $queryFunction

        }
    }

    Context "Decrypt Stored Procedure" {
        It "Should be successful" {
            $result = Invoke-DbaDbDecryptObject -SqlInstance $script:instance1 -Database $dbname -ObjectName DummyEncryptedFunctionStoredProcedure
            $result
            $result.Script | Should Be $queryStoredProcedure

        }
    }

}