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
        Specifies the full file path of the output file. The file must end with .xml or .regsrvr

    .PARAMETER InputObject
        Enables piping from Get-DbaRegServer, Get-DbaRegServerGroup, CSVs and other objects.

        If importing from CSV or other object, a column named ServerName is required. Optional columns include Name, Description and Group.

    .PARAMETER Group
        Specifies one or more groups to include.

    .PARAMETER ExcludeGroup
        Specifies one or more groups to exclude.

    .PARAMETER Overwrite
        Specifies to overwrite the output file (FilePath) if it already exists.

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
        [System.IO.FileInfo]$FilePath,
        [ValidateSet("None", "PersistLoginName", "PersistLoginNameAndPassword")]
        [string]$CredentialPersistenceType = "None",
        [object[]]$Group,
        [object[]]$ExcludeGroup,
        [switch]$Overwrite,
        [switch]$EnableException
    )
    begin {
        $null = Test-ExportDirectory -Path $Path
        $timeNow = (Get-Date -UFormat "%m%d%Y%H%M%S")

        # ValidateScript in the above param block relies on the order of the params specified by the user,
        # so the creation of the file path and $Overwrite are evaluated here
        if ($PSBoundParameters.ContainsKey("FilePath")) {
            if ($FilePath.FullName -notmatch "\.xml$|\.regsrvr$") {
                Stop-Function -Message "The FilePath specified must end with either .xml or .regsrvr"
                return
            }

            if (-not (Test-Path $FilePath) ) {
                New-Item -Path $FilePath.DirectoryName -ItemType "directory" -Force | Out-Null # make sure the parent dir exists
            } elseif (-not $Overwrite.IsPresent) {
                Stop-Function -Message "Use the -Overwrite parameter if the file $FilePath should be overwritten."
                return
            }
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }

        foreach ($instance in $SqlInstance) {
            if ($PSBoundParameters.ContainsKey("Group")) {
                if ($PSBoundParameters.ContainsKey("ExcludeGroup")) {
                    $InputObject += Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group -ExcludeGroup $ExcludeGroup
                } else {
                    $InputObject += Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group
                }
            } elseif ($PSBoundParameters.ContainsKey("ExcludeGroup")) {
                $InputObject += Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -ExcludeGroup $ExcludeGroup
            } else {
                $InputObject += Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Id 1 # legacy behavior to return -Id 1 which means return everything
            }
        }

        foreach ($object in $InputObject) {
            try {
                if ($object -is [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore]) {
                    if ($PSBoundParameters.ContainsKey("Group")) {
                        if ($PSBoundParameters.ContainsKey("ExcludeGroup")) {
                            $object = Get-DbaRegServerGroup -SqlInstance $object.ParentServer -Group $Group -ExcludeGroup $ExcludeGroup
                        } else {
                            $object = Get-DbaRegServerGroup -SqlInstance $object.ParentServer -Group $Group
                        }
                    } elseif ($PSBoundParameters.ContainsKey("ExcludeGroup")) {
                        $InputObject += Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -ExcludeGroup $ExcludeGroup
                    } else {
                        $object = Get-DbaRegServerGroup -SqlInstance $object.ParentServer -Id 1 # legacy behavior to return -Id 1 which means return everything
                    }
                }

                if (($object -is [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer]) -or ($object -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup])) {
                    $regname = $object.Name.Replace('\', '$')
                    $OutputFilePath = $null

                    if (-not $PSBoundParameters.ContainsKey("FilePath")) {
                        $ExportFileName = $null
                        $serverName = $object.SqlInstance.Replace('\', '$');

                        if ($object -is [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer]) {
                            $ExportFileName = "$serverName-regserver-$regname-$timeNow.xml"
                        } elseif ($object -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]) {
                            $ExportFileName = "$serverName-reggroup-$regname-$timeNow.xml"
                        }

                        $OutputFilePath = Join-DbaPath -Path $Path -Child $ExportFileName
                    } elseif ($InputObject.length -gt 1) {
                        # more than one group was passed in, so we need to add the group name to the FilePath because there will be multiple files generated.
                        $extension = [IO.Path]::GetExtension($FilePath.FullName)
                        $OutputFilePath = $FilePath.FullName.Replace($extension, "-" + $regname + $extension)
                    } else {
                        $OutputFilePath = $FilePath.FullName
                    }

                    $object.Export($OutputFilePath, $CredentialPersistenceType)

                    Get-ChildItem $OutputFilePath -ErrorAction Stop
                } else {
                    Stop-Function -Message "InputObject is not a registered server or server group" -Continue
                }
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_
            }
        }
    }
}