function Get-LoginPasswordHash {
    <#
    .SYNOPSIS
        Internal function. Gets the hashed password value for a SQL Server login.

    .DESCRIPTION
        Retrieves the hashed password value for SQL Server logins using the same technique as Microsoft's sp_help_revlogin stored procedure.
        This allows passwords to be transferred between instances without needing to know the clear-text password.

    .PARAMETER Login
        The Login object from SMO containing the login to get the password hash for.

    .NOTES
        Author: Shawn Melton (@wsmelton), http://www.wsmelton.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-LoginPasswordHash

    .EXAMPLE
        PS C:\> $login = Get-DbaLogin -SqlInstance sql2017 -Login testuser
        PS C:\> Get-LoginPasswordHash -Login $login

        Returns the hashed password value for the testuser login on sql2017.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [Microsoft.SqlServer.Management.Smo.Login]$Login
    )

    begin {
        $server = $Login.Parent
    }

    process {
        # Only SQL Server logins have password hashes
        if ($Login.LoginType -ne "SqlLogin") {
            Write-Message -Level Warning -Message "Login $($Login.Name) is not a SQL Server login. Password hash cannot be retrieved."
            return
        }

        # Build the query based on SQL Server version
        $sql = switch ($server.VersionMajor) {
            8 {
                # SQL Server 2000
                "SELECT CONVERT(VARBINARY(256), password) as hashedpass FROM master.dbo.sysxlogins WHERE name = '$($Login.Name)'"
            }
            9 {
                # SQL Server 2005
                "SELECT CONVERT(VARBINARY(256), password_hash) as hashedpass FROM sys.sql_logins WHERE name = '$($Login.Name)'"
            }
            default {
                # SQL Server 2008 and above
                "SELECT CAST(CONVERT(varchar(256), CAST(LOGINPROPERTY(name, 'PasswordHash') AS VARBINARY(256)), 1) AS NVARCHAR(max)) as hashedpass FROM sys.server_principals WHERE principal_id = $($Login.ID)"
            }
        }

        try {
            $hashedPass = $server.ConnectionContext.ExecuteScalar($sql)
        } catch {
            try {
                $hashedPassDt = $server.Databases["master"].ExecuteWithResults($sql)
                $hashedPass = $hashedPassDt.Tables[0].Rows[0].Item(0)
            } catch {
                Stop-Function -Message "Failed to retrieve password hash for login $($Login.Name)" -ErrorRecord $_ -Target $Login -Continue
                return
            }
        }

        # Convert byte array to hex string if needed
        if ($hashedPass.GetType().Name -ne "String") {
            $passString = "0x"
            $hashedPass | ForEach-Object {
                $passString += ("{0:X}" -f $_).PadLeft(2, "0")
            }
            $hashedPass = $passString
        }

        return $hashedPass
    }
}
