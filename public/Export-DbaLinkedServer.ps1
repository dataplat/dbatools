function Export-DbaLinkedServer {
    <#
    .SYNOPSIS
        Generates T-SQL scripts to recreate linked server configurations with their login credentials.

    .DESCRIPTION
        Creates executable T-SQL scripts from existing linked server definitions, including remote login mappings and passwords. Perfect for migrating linked servers between environments, creating disaster recovery scripts, or documenting your linked server landscape. When passwords are included, the function accesses the local registry to decrypt stored credentials, so the generated scripts contain actual working passwords rather than placeholder values.

    .PARAMETER SqlInstance
        Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2005 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Credential
        Login to the target OS using alternative credentials. Accepts credential objects (Get-Credential)

        Only used when passwords are being exported, as it requires access to the Windows OS via PowerShell remoting to decrypt the passwords.

    .PARAMETER Path
        Specifies the directory where the linked server export file will be created. Defaults to the configured DbatoolsExport path.
        Use this when you need the script saved to a specific folder location for organization or deployment purposes.

    .PARAMETER FilePath
        Specifies the complete file path and name for the exported T-SQL script, including the .sql extension.
        Use this when you need precise control over the output filename and location, overriding the automatic naming from Path parameter.

    .PARAMETER LinkedServer
        Specifies one or more linked server names to export, supporting wildcards for pattern matching. If not specified, all linked servers on the instance will be exported.
        Use this when you need to export specific linked servers rather than the entire linked server configuration from an instance.

    .PARAMETER InputObject
        Accepts linked server objects piped from Get-DbaLinkedServer, allowing you to filter and process specific linked servers before export.
        Use this when you want to chain commands together, such as first getting linked servers with specific criteria then exporting only those results.

    .PARAMETER ExcludePassword
        Excludes actual passwords from the exported script, replacing them with placeholder values for security purposes.
        Use this when sharing scripts across environments or with team members where you need the linked server structure but want to protect sensitive credentials.

    .PARAMETER Append
        Adds the exported linked server scripts to an existing file instead of overwriting it.
        Use this when combining multiple linked server exports into a single deployment script or building comprehensive migration scripts over multiple runs.

    .PARAMETER Passthru
        Returns the generated T-SQL script to the PowerShell pipeline instead of saving to file.
        Use this to capture the script in a variable, pipe to other commands, or display directly in the console.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: LinkedServer
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbaLinkedServer

    .EXAMPLE
        PS C:\> Export-DbaLinkedServer -SqlInstance sql2017 -Path C:\temp\ls.sql

        Exports the linked servers, including passwords, from sql2017 to the file C:\temp\ls.sql

    .EXAMPLE
        PS C:\> Export-DbaLinkedServer -SqlInstance sql2017 -Path C:\temp\ls.sql -ExcludePassword

        Exports the linked servers, without passwords, from sql2017 to the file C:\temp\ls.sql

    .EXAMPLE
        PS C:\> Export-DbaLinkedServer -SqlInstance sql2017 -Passthru

        Returns the T-SQL script for linked servers to the console instead of writing to a file

    .OUTPUTS
        System.String (when -Passthru is specified or when no -Path/-FilePath is provided)

        Returns the generated T-SQL script as a string or array of strings. The script contains the necessary T-SQL commands to recreate the linked server configuration on another SQL Server instance.

        System.IO.FileInfo (when -Path or -FilePath is specified)

        Returns file information for the exported T-SQL script file. Properties include:
        - FullName: Complete file path including filename
        - Name: The filename (e.g., "sql2017_linkedservers.sql")
        - Directory: The directory where the file is located
        - Length: File size in bytes
        - LastWriteTime: Timestamp of when the file was created or last modified

    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [string[]]$LinkedServer,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [Alias("OutFile", "FileName")]
        [string]$FilePath,
        [switch]$ExcludePassword,
        [switch]$Append,
        [switch]$Passthru,
        [Microsoft.SqlServer.Management.Smo.LinkedServer[]]$InputObject,
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
                if (-not $ExcludePassword) {
                    Write-Message -Level Verbose -Message "Opening dedicated admin connection for password retrieval."
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9 -DedicatedAdminConnection -WarningAction SilentlyContinue
                } else {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
                }
                $InputObject += $server.LinkedServers
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($LinkedServer) {
                $InputObject = $InputObject | Where-Object Name -in $LinkedServer
            }

            if (-not $InputObject) {
                Write-Message -Level Verbose -Message "Nothing to export"
                continue
            }

            $FilePath = Get-ExportFilePath -Path $PSBoundParameters.Path -FilePath $PSBoundParameters.FilePath -Type sql -ServerName $instance

            $sql = @()

            if ($ExcludePassword) {
                $sql += $InputObject.Script()
            } else {
                try {
                    $decrypted = Get-DecryptedObject -SqlInstance $server -Credential $Credential -Type LinkedServer -EnableException
                } catch {
                    Stop-Function -Continue -Message "Failure" -ErrorRecord $_
                }

                foreach ($ls in $InputObject) {
                    $currentls = $decrypted | Where-Object Name -eq $ls.Name
                    if ($currentls.Password) {
                        $tempsql = $ls.Script()
                        foreach ($map in $currentls) {
                            if ($map.Identity -isnot [dbnull]) {
                                $rmtuser = $map.Identity.Replace("'", "''")
                                $password = $map.Password.Replace("'", "''")
                            }
                            $tempsql = $tempsql.Replace(' /* For security reasons the linked server remote logins password is changed with ######## */', '')
                            $tempsql = $tempsql.Replace("rmtuser=N'$rmtuser',@rmtpassword='########'", "rmtuser=N'$rmtuser',@rmtpassword='$password'")
                        }
                        $sql += $tempsql
                    } else {
                        $sql += $ls.Script()
                    }
                }
            }
            if ($Passthru) {
                $sql
            } elseif ($Path -or $FilePath) {
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
            } else {
                $sql
            }

            # Disconnect DAC connection if it was opened
            if (-not $ExcludePassword) {
                $null = $server | Disconnect-DbaInstance -WhatIf:$false
            }
        }
    }
}