function Get-LoginPasswordHash {
    <#
    .SYNOPSIS
    Query a given Instance to obtain the password hash based on SQL Servers encryption

    .EXAMPLE
    Get-LoginPasswordHash -Server (Connect-DbaInstance -SqlInstance someInstance) -Login (Get-DbaLogin ...-Login TestLogin1)

    Return the object with the Login and PasswordHashValue for TestLogin1
    .NOTES
    Query was pulled from sp_help_revlogin procedure published by Microsoft
    https://learn.microsoft.com/en-US/troubleshoot/sql/database-engine/security/transfer-logins-passwords-between-instances

    .OUTPUT
    System.Collections.Hashtable
    #>
    [CmdletBinding()]
    [OutputType('System.Collections.Hashtable')]
    param(
        # Input object expected from Connect-DbaInstance
        [Microsoft.SqlServer.Management.Smo.Server]$Server,

        # Login names to process
        [object[]]$Login
    )
    begin {
        <#
            If the login does not exist this will not error.
            The PasswordHashValue property will simply contain only 0x as a value.
            So because of that there is no error handling included as an internal.
            Calling function should handle login lookup.
        #>
        $query = "
        /* varbinary --> hex */
        DECLARE @binvalue varbinary(256)

        SET @binvalue = CAST( LOGINPROPERTY( @name, 'PasswordHash' ) AS varbinary (256) )
        BEGIN
            DECLARE @charvalue varchar (514)
            DECLARE @i int
            DECLARE @length int
            DECLARE @hexstring char(16)
            SELECT @charvalue = '0x'
            SELECT @i = 1
            SELECT @length = DATALENGTH (@binvalue)
            SELECT @hexstring = '0123456789ABCDEF'

            WHILE (@i <= @length)
            BEGIN
                DECLARE @tempint int
                DECLARE @firstint int
                DECLARE @secondint int
                SELECT @tempint = CONVERT(int, SUBSTRING(@binvalue,@i,1))
                SELECT @firstint = FLOOR(@tempint/16)
                SELECT @secondint = @tempint - (@firstint*16)
                SELECT @charvalue = @charvalue + SUBSTRING(@hexstring, @firstint+1, 1) + SUBSTRING(@hexstring, @secondint+1, 1)
                SELECT @i = @i + 1
            END
            SELECT @name AS Login, @charvalue AS PasswordHashValue
        END"
    }
    process {
        foreach ($l in $Login) {
            $invokeParams = @{
                SqlInstance  = $Server
                Query        = $query
                As           = 'DataRow'
                SqlParameter = @{ Name = $l }
            }
            Invoke-DbaQuery @invokeParams -EnableException | ForEach-Object {
                @{ $_.Login = $_.PasswordHashValue }
            }
        }
    }
}