function Export-DbaRegServer {
    <#
    .SYNOPSIS
        Exports registered servers and registered server groups to file

    .DESCRIPTION
        Exports registered servers and registered server groups to file

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER CredentialPersistenceType
        Used to specify how the login and passwords are persisted. Valid values include None, PersistLoginName and PersistLoginNameAndPassword.

    .PARAMETER Path
        Specifies the directory where the file or files will be exported.

    .PARAMETER FilePath
        Specifies the full file path of the output file.

    .PARAMETER InputObject
        Enables piping from Get-DbaRegServer, Get-DbaRegServerGroup, CSVs and other objects.

        If importing from CSV or other object, a column named ServerName is required. Optional columns include Name, Description and Group.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.

        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.

        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: RegisteredServer, CMS
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Export-DbaRegServer

    .EXAMPLE
        PS C:\> Export-DbaRegServer -SqlInstance sql2008

        Exports all Registered Server and Registered Server Groups on sql2008 to an automatically generated file name in the current directory

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sql2008, sql2012 | Export-DbaRegServer

        Exports all registered servers on sql2008 and sql2012. Warning - each one will have its own individual file. Consider piping groups.

    .EXAMPLE
        PS C:\> Get-DbaRegServerGroup -SqlInstance sql2008, sql2012 | Export-DbaRegServer

        Exports all registered servers on sql2008 and sql2012, organized by group.

    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingPlainTextForPassword", "", Justification = "For Parameter CredentialPersistenceType")]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [string]$Path = (Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport'),
        [Alias("OutFile", "FileName")]
        [string]$FilePath,
        [ValidateSet("None", "PersistLoginName", "PersistLoginNameAndPassword")]
        [string]$CredentialPersistenceType = "None",
        [switch]$EnableException
    )
    begin {
        $null = Test-ExportDirectory -Path $Path
        $timeNow = (Get-Date -uformat "%m%d%Y%H%M%S")
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            $InputObject += Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Id 1
        }

        foreach ($object in $InputObject) {
            try {
                if ($object -is [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore]) {
                    $object = Get-DbaRegServerGroup -SqlInstance $object.ParentServer -Id 1
                }
                if ($object -is [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer]) {
                    if (-not $FilePath) {
                        $serverName = $object.SqlInstance.Replace('\', '$');
                        $regservername = $object.Name.Replace('\', '$')
                        $ExportFileName = "$serverName-regserver-$regservername-$timeNow.xml"
                        $FilePath = Join-DbaPath -Path $Path -Child $ExportFileName
                        $object.Export($FilePath, $CredentialPersistenceType)
                    }
                } elseif ($object -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]) {
                    if (-not $FilePath) {
                        $servername = $object.SqlInstance.Replace('\', '$')
                        $regservergroup = $object.Name.Replace('\', '$')
                        $ExportFileName = "$serverName-reggroup-$regservergroup-$timeNow.xml"
                        $FilePath = Join-DbaPath -Path $Path -Child $ExportFileName
                        $object.Export($FilePath, $CredentialPersistenceType)
                    }
                } else {
                    Stop-Function -Message "InputObject is not a registered server or server group" -Continue
                }
                Get-ChildItem $FilePath -ErrorAction Stop
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_
            }
        }
    }
}