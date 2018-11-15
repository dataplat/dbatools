function Export-DbaCredential {
    <#
    .SYNOPSIS
        Exports credentials INCLUDING PASSWORDS, unless specified otherwise, to sql file.

    .DESCRIPTION
        Exports credentials INCLUDING PASSWORDS, unless specified otherwise, to sql file.

        Requires remote Windows access if exporting the password.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

    .PARAMETER Credential
        Login to the target OS using alternative credentials. Accepts credential objects (Get-Credential)

    .PARAMETER Path
        The path to the exported sql file.

    .PARAMETER Identity
        The credentials to export. If unspecified, all credentials will be exported.

    .PARAMETER InputObject
        Allow credentials to be piped in from Get-DbaCredential

    .PARAMETER ExcludePassword
        Exports the SQL credential without any sensitive information.

    .PARAMETER InputObject
        Allow credentials to be piped in from Get-DbaCredential

    .PARAMETER Append
        Append to Path

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

    .EXAMPLE
        PS C:\> Export-DbaCredential -SqlInstance sql2017 -Path C:\temp\cred.sql

        Exports credentials, including passwords, from sql2017 to the file C:\temp\cred.sql

    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [string[]]$Identity,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [string]$Path,
        [switch]$ExcludePassword,
        [switch]$Append,
        [Microsoft.SqlServer.Management.Smo.Credential[]]$InputObject,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential -MinimumVersion 9
                $InputObject += $server.Credentials
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Identity) {
                $InputObject = $InputObject | Where-Object Identity -in $Identity
            }

            if (!(Test-SqlSa -SqlInstance $instance -SqlCredential $sqlcredential)) {
                Stop-Function -Message "Not a sysadmin on $instance. Quitting." -Target $instance -Continue
            }

            Write-Message -Level Verbose -Message "Getting NetBios name for $instance."
            $sourceNetBios = Resolve-NetBiosName $server

            Write-Message -Level Verbose -Message "Checking if Remote Registry is enabled on $instance."
            try {
                Invoke-Command2 -Raw -Credential $Credential -ComputerName $sourceNetBios -ScriptBlock { Get-ItemProperty -Path "HKLM:\SOFTWARE\" } -ErrorAction Stop
            } catch {
                Stop-Function -Message "Can't connect to registry on $instance." -Target $sourceNetBios -ErrorRecord $_
                return
            }

            if (-not (Test-Bound -ParameterName Path)) {
                $timenow = (Get-Date -uformat "%m%d%Y%H%M%S")
                $mydocs = [Environment]::GetFolderPath('MyDocuments')
                $path = "$mydocs\$($server.name.replace('\', '$'))-$timenow-credential.sql"
            }

            $sql = @()

            if ($ExcludePassword) {
                Stop-Function -Message "So sorry, there's no other way around it for now. The password has to be exported in plain text."
                return
            } else {
                try {
                    $creds = Get-DecryptedObject -SqlInstance $server -Type Credential
                } catch {
                    Stop-Function -Continue -Message "Failure" -ErrorRecord $_
                }
                foreach ($currentCred in $creds) {
                    $name = $currentCred.Name.Replace("'", "''")
                    $identity = $currentCred.Identity.Replace("'", "''")
                    $password = $currentCred.Password.Replace("'", "''")
                    $sql += "CREATE CREDENTIAL $name WITH IDENTITY = N'$identity', SECRET = N'$password'"
                }
            }

            try {
                if ($Append) {
                    Add-Content -Path $path -Value $sql
                } else {
                    Set-Content -Path $path -Value $sql
                }
                Get-ChildItem -Path $path
            } catch {
                Stop-Function -Message "Can't write to $path" -ErrorRecord $_ -Continue
            }


            Write-Message -Level Verbose -Message "Attempting to migrate $credentialName"
            Get-ChildItem -Path $path
        }
    }
}