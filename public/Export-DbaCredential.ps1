function Export-DbaCredential {
    <#
    .SYNOPSIS
        Exports SQL Server credentials to executable T-SQL CREATE CREDENTIAL scripts

    .DESCRIPTION
        Exports SQL Server credentials to T-SQL files containing CREATE CREDENTIAL statements that can recreate the credentials on another instance. By default, this includes decrypted passwords, making it perfect for migration scenarios where you need to move credentials between servers.

        The function generates executable T-SQL scripts that DBAs can run to recreate credentials during migrations, disaster recovery, or when setting up new environments. When passwords are included, the function requires sysadmin privileges and remote Windows registry access to decrypt the stored secrets.

        Use the ExcludePassword parameter to export credential definitions without sensitive data for documentation or security-conscious scenarios.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Credential
        Login to the target OS using alternative credentials. Accepts credential objects (Get-Credential)

        Only used when passwords are being exported, as it requires access to the Windows OS via PowerShell remoting to decrypt the passwords.

    .PARAMETER Path
        Specifies the directory where the exported T-SQL script file will be saved. Defaults to the configured DbatoolsExport path.
        Use this when you want to control where credential scripts are stored for organization or compliance requirements.

    .PARAMETER FilePath
        Specifies the complete file path and name for the exported T-SQL script. Overrides the Path parameter when specified.
        Use this when you need precise control over the output file name and location, especially for automated processes.

    .PARAMETER Identity
        Specifies which credential names to export by filtering on the Identity property. Accepts an array of credential names.
        Use this to export specific credentials instead of all credentials, particularly useful when migrating only certain application or service accounts.

    .PARAMETER ExcludePassword
        Exports credential definitions without the actual password values, replacing them with placeholder text.
        Use this for documentation purposes or when you need credential structure without sensitive data for security reviews.

    .PARAMETER Append
        Adds the exported credential scripts to an existing file instead of overwriting it.
        Use this when consolidating credentials from multiple instances into a single deployment script.

    .PARAMETER Passthru
        Returns the generated T-SQL script to the PowerShell pipeline instead of saving to file.
        Use this to capture the script in a variable, pipe to other commands, or display directly in the console.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Credential
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbaCredential

    .OUTPUTS
        System.IO.FileInfo

        Returns a file object representing the exported T-SQL script file(s) containing the CREATE CREDENTIAL statements. One file is returned for each SQL Server instance from which credentials were exported.

        Properties:
        - FullName: The complete path to the exported script file
        - Name: The name of the exported script file
        - Length: The size of the exported file in bytes
        - LastWriteTime: The date and time the file was created or last modified
        - Directory: The directory containing the exported file

    .EXAMPLE
        PS C:\> Export-DbaCredential -SqlInstance sql2017 -Path C:\temp\cred.sql

        Exports credentials, including passwords, from sql2017 to the file C:\temp\cred.sql

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [Alias("OutFile", "FileName")]
        [string]$FilePath,
        [string[]]$Identity,
        [switch]$ExcludePassword,
        [switch]$Append,
        [switch]$Passthru,
        [switch]$EnableException
    )
    begin {
        $null = Test-ExportDirectory -Path $Path
    }
    process {
        if (Test-FunctionInterrupt) { return }

        if ($IsLinux -or $IsMacOS) {
            Stop-Function -Message "This command is not supported on Linux or macOS"
            return
        }

        foreach ($instance in $SqlInstance) {
            try {
                # Do we need a dedicated admin connection to the source for password retrieval?
                # If passwords are excluded, we don't need a DAC
                if ($ExcludePassword) { $dacNeeded = $false } else { $dacNeeded = $true }

                # Do we have a dedicated admin connection already?
                $dacConnected = $instance.Type -eq 'Server' -and $instance.InputObject.Name -match '^ADMIN:'

                $dacOpened = $false
                if ($dacNeeded) {
                    if ($dacConnected) {
                        Write-Message -Level Verbose -Message "Reusing dedicated admin connection for password retrieval."
                        $server = $instance.InputObject
                    } else {
                        Write-Message -Level Verbose -Message "Opening dedicated admin connection for password retrieval."
                        $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9 -DedicatedAdminConnection -WarningAction SilentlyContinue
                        $dacOpened = $true
                    }
                } else {
                    Write-Message -Level Verbose -Message "Opening or reusing normal connection because passwords are excluded."
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
                }
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($ExcludePassword) {
                $credentials = foreach ($cred in $server.Credentials) {
                    [PSCustomObject]@{
                        Name            = $cred.Name
                        Quotename       = $server.Query("SELECT QUOTENAME('$($cred.Name.Replace("'", "''"))') AS Quotename").Quotename
                        Identity        = $cred.Identity.ToString()
                        Password        = '<EnterStrongPasswordHere>'
                        MappedClassType = $cred.MappedClassType
                        ProviderName    = $cred.ProviderName
                    }
                }
            } else {
                $credentials = Get-DecryptedObject -SqlInstance $server -Credential $Credential -Type Credential -EnableException
            }

            if ($Identity) {
                $credentials = $credentials | Where-Object Identity -in $Identity
            }

            if (-not $credentials) {
                Write-Message -Level Verbose -Message "Nothing to export"
                continue
            }

            $FilePath = Get-ExportFilePath -Path $PSBoundParameters.Path -FilePath $PSBoundParameters.FilePath -Type sql -ServerName $instance

            $sql = @()

            foreach ($cred in $credentials) {
                $quotename = $cred.Quotename
                $identity = $cred.Identity.Replace("'", "''")
                $password = $cred.Password.Replace("'", "''")
                $cryptoSql = ""
                if ($cred.MappedClassType -like 'Cryptographic*') {
                    $providerName = $cred.ProviderName
                    $cryptoSql = " FOR CRYPTOGRAPHIC PROVIDER $providerName"
                }
                $sql += "CREATE CREDENTIAL $quotename WITH IDENTITY = N'$identity', SECRET = N'$password'" + $cryptoSql
            }

            if ($Passthru) {
                $sql
            } else {
                try {
                    if ($Append) {
                        Add-Content -Path $FilePath -Value $sql
                    } else {
                        Set-Content -Path $FilePath -Value $sql
                    }
                    Get-ChildItem -Path $FilePath
                } catch {
                    Stop-Function -Message "Can't write to $FilePath" -ErrorRecord $_ -Continue
                }
            }

            if ($dacOpened) {
                $null = $server | Disconnect-DbaInstance -WhatIf:$false
            }
        }
    }
}