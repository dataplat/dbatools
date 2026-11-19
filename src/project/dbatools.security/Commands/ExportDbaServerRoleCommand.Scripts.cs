#nullable enable

namespace Dataplat.Dbatools.Commands;

// Hop script constant (the verbatim retired PS process body) - split out per the repo 400-line file limit.
public sealed partial class ExportDbaServerRoleCommand
{

    // PS: the begin body, the process body (dot-sourced, run only when a record was processed), and
    // the end body VERBATIM. Substitutions only: -FunctionName on every direct Stop-Function/Write-Message;
    // Test-Bound on ScriptingOptionsObject -> the carried flag; $PSBoundParameters.Path/.FilePath -> the
    // carried bound values; and $MyInvocation.MyCommand.Name -> the literal command name (a hop scriptblock
    // cannot resolve the public command identity). The two config-value defaults and the process/end split
    // are hop adaptations described in the class remarks. There is no ShouldProcess in this command.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $__batches, $ScriptingOptionsObject, $ServerRole, $ExcludeServerRole, $Path, $FilePath, $BatchSeparator, $Encoding, $ExcludeFixedRole, $IncludeRoleMember, $Passthru, $NoClobber, $Append, $NoPrefix, $EnableException, $__pathBound, $__batchSepBound, $__scriptingBound, $__boundPathValue, $__boundFilePathValue, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [System.Management.Automation.PSCredential]$SqlCredential, $__batches, [Microsoft.SqlServer.Management.Smo.ScriptingOptions]$ScriptingOptionsObject, [string[]]$ServerRole, [string[]]$ExcludeServerRole, [string]$Path, [string]$FilePath, [string]$BatchSeparator, [string]$Encoding, $ExcludeFixedRole, $IncludeRoleMember, $Passthru, $NoClobber, $Append, $NoPrefix, $EnableException, $__pathBound, $__batchSepBound, $__scriptingBound, $__boundPathValue, $__boundFilePathValue, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    if (-not $__pathBound) { $Path = Get-DbatoolsConfigValue -FullName 'Path.DbatoolsExport' }
    if (-not $__batchSepBound) { $BatchSeparator = Get-DbatoolsConfigValue -FullName 'Formatting.BatchSeparator' }

        $null = Test-ExportDirectory -Path $Path
        $outsql = @()
        $outputFileArray = @()
        $roleCollection = New-Object System.Collections.ArrayList
        if ($IsLinux -or $IsMacOs) {
            $executingUser = $env:USER
        } else {
            $executingUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        }
        $commandName = "Export-DbaServerRole"

        $roleSQL = "SELECT
                    CASE sperm.state
                        WHEN 'D' THEN 'DENY'
                        WHEN 'G' THEN 'GRANT'
                        WHEN 'R' THEN 'REVOKE'
                        WHEN 'W' THEN 'GRANT'
                    END AS GrantState,
                    sperm.permission_name AS Permission,
                    CASE
                        WHEN sperm.class = 100 THEN ''
                        WHEN sperm.class = 101 AND sp2.type = 'S' THEN 'ON LOGIN::' + QUOTENAME(sp2.name)
                        WHEN sperm.class = 101 AND sp2.type = 'R' THEN 'ON SERVER ROLE::' + QUOTENAME(sp2.name)
                        WHEN sperm.class = 101 AND sp2.type = 'U' THEN 'ON LOGIN::' + QUOTENAME(sp2.name)
                        WHEN sperm.class = 105 THEN 'ON ENDPOINT::' + QUOTENAME(ep.name)
                        WHEN sperm.class = 108 THEN 'ON AVAILABILITY GROUP::' + QUOTENAME(ag.name)
                        ELSE ''
                    END AS OnClause,
                    QUOTENAME(sp.name) AS RoleName,
                    CASE
                        WHEN sperm.state = 'W' THEN 'WITH GRANT OPTION AS ' + QUOTENAME(gsp.name)
                        ELSE ''
                    END AS GrantOption
                FROM sys.server_permissions sperm
                INNER JOIN sys.server_principals sp
                    ON sp.principal_id = sperm.grantee_principal_id
                INNER JOIN sys.server_principals gsp
                    ON gsp.principal_id = sperm.grantor_principal_id
                LEFT JOIN sys.endpoints ep
                    ON ep.endpoint_id = sperm.major_id
                    AND sperm.class = 105
                LEFT JOIN sys.server_principals sp2
                    ON sp2.principal_id = sperm.major_id
                    AND sperm.class = 101
                LEFT JOIN
                (
                    SELECT
                        ar.replica_metadata_id,
                        ag.name
                    FROM sys.availability_groups ag
                    INNER JOIN sys.availability_replicas ar
                        ON ag.group_id = ar.group_id
                ) ag
                    ON ag.replica_metadata_id = sperm.major_id
                    AND sperm.class = 108
                WHERE sp.type='R'
                AND sp.name=N'/*RoleName*/'"

        if (-not $__scriptingBound) {
            $ScriptingOptionsObject = New-DbaScriptingOption
            $ScriptingOptionsObject.AllowSystemObjects = $false
            $ScriptingOptionsObject.ContinueScriptingOnError = $false
            $ScriptingOptionsObject.IncludeDatabaseContext = $true
            $ScriptingOptionsObject.IncludeIfNotExists = $true
            $ScriptingOptionsObject.ScriptOwner = $true
        }

        if ($ScriptingOptionsObject.NoCommandTerminator) {
            $commandTerminator = ''
        } else {
            $commandTerminator = ';'
        }
        $outsql = @()
    foreach ($__batch in $__batches) {
        $InputObject = $__batch
        . {
        if (Test-FunctionInterrupt) {
            return
        }

        if (-not $InputObject -and -not $SqlInstance) {
            Stop-Function -Message "You must pipe in a ServerRole or server or specify a SqlInstance" -FunctionName Export-DbaServerRole
            return
        }

        if ($SqlInstance) {
            $InputObject = $SqlInstance
        }

        foreach ($input in $InputObject) {
            $inputType = $input.GetType().FullName
            switch ($inputType) {
                'Dataplat.Dbatools.Parameter.DbaInstanceParameter' {
                    Write-Message -Level Verbose -Message "Processing DbaInstanceParameter through InputObject" -FunctionName Export-DbaServerRole -ModuleName "dbatools"
                    $serverRoles = Get-DbaServerRole -SqlInstance $input -SqlCredential $SqlCredential  -ServerRole $ServerRole -ExcludeServerRole $ExcludeServerRole -ExcludeFixedRole:$ExcludeFixedRole
                }
                'Microsoft.SqlServer.Management.Smo.Server' {
                    Write-Message -Level Verbose -Message "Processing Server through InputObject" -FunctionName Export-DbaServerRole -ModuleName "dbatools"
                    $serverRoles = Get-DbaServerRole -SqlInstance $input -SqlCredential $SqlCredential -ServerRole $ServerRole -ExcludeServerRole $ExcludeServerRole -ExcludeFixedRole:$ExcludeFixedRole
                }
                'Microsoft.SqlServer.Management.Smo.ServerRole' {
                    Write-Message -Level Verbose -Message "Processing ServerRole through InputObject" -FunctionName Export-DbaServerRole -ModuleName "dbatools"
                    $serverRoles = $input
                }
                default {
                    Stop-Function -Message "InputObject is not a server or serverrole." -FunctionName Export-DbaServerRole
                    return
                }
            }

            foreach ($role in $serverRoles) {
                $server = $role.Parent

                if ($server.ServerType -eq 'SqlAzureDatabase') {
                    Stop-Function -Message "The SqlAzureDatabase - $server is not supported." -Continue -FunctionName Export-DbaServerRole
                }

                try {
                    # Get user defined Server roles
                    if ($server.VersionMajor -ge 11) {
                        $outsql += $role.Script($ScriptingOptionsObject)

                        $query = $roleSQL.Replace('/*RoleName*/', "$($role.Name)")
                        $rolePermissions = $server.Query($query)

                        foreach ($rolePermission in $rolePermissions) {
                            $script = $rolePermission.GrantState + " " + $rolePermission.Permission
                            if ($rolePermission.OnClause) {
                                $script += " " + $rolePermission.OnClause
                            }
                            if ($rolePermission.RoleName) {
                                $script += " TO " + $rolePermission.RoleName
                            }
                            if ($rolePermission.GrantOption) {
                                $script += " " + $rolePermission.GrantOption + $commandTerminator
                            } else {
                                $script += $commandTerminator
                            }
                            $outsql += "$script"
                        }
                    }

                    if ($IncludeRoleMember) {
                        foreach ($roleUser in $role.Login) {
                            $script = 'ALTER SERVER ROLE [' + $role.Role + "] ADD MEMBER [" + $roleUser + "]" + $commandTerminator
                            $outsql += "$script"
                        }
                    }
                    if ($outsql) {
                        $roleObject = [PSCustomObject]@{
                            Name     = $role.Name
                            Instance = $role.SqlInstance
                            Sql      = $outsql
                        }
                        $roleCollection.Add($roleObject) | Out-Null
                    }
                    $outsql = @()
                } catch {
                    $outsql = @()
                    Stop-Function -Message "Error occurred processing role $Role" -Category ConnectionError -ErrorRecord $_ -Target $role.SqlInstance -Continue -FunctionName Export-DbaServerRole
                }
            }
        }
        }
    }
        # Named-wrapper shim (W2-208): the END/emit phase runs inside a function carrying the command's
        # name so Get-ExportFilePath's (Get-PSCallStack)[1].Command default-filename resolves to
        # Export-DbaServerRole, not <ScriptBlock> (which produced invalid -<scriptblock>.sql names).
        function Export-DbaServerRole {
        if (Test-FunctionInterrupt) { return }

        $eol = [System.Environment]::NewLine

        $timeNow = $(Get-Date -Format (Get-DbatoolsConfigValue -FullName 'Formatting.DateTime'))
        foreach ($role in $roleCollection) {
            $instanceName = $role.Instance

            if ($NoPrefix) {
                $prefix = $null
            } else {
                $prefix = "/*$eol`tCreated by $executingUser using dbatools $commandName for objects on $instanceName.$databaseName at $timeNow$eol`tSee https://dbatools.io/$commandName for more information$eol*/"
            }

            if ($BatchSeparator) {
                $sql = $role.SQL -join "$eol$BatchSeparator$eol"
                #add the final GO
                $sql += "$eol$BatchSeparator"
            } else {
                $sql = $role.SQL
            }

            if ($Passthru) {
                if ($null -ne $prefix) {
                    $sql = "$prefix$eol$sql"
                }
                $sql
            } elseif ($Path -Or $FilePath) {
                $outputFileName = $instanceName.Replace('\', '$')
                if ($outputFileArray -notcontains $outputFileName) {
                    Write-Message -Level Verbose -Message "New File $outputFileName " -FunctionName Export-DbaServerRole -ModuleName "dbatools"
                    if ($null -ne $prefix) {
                        $sql = "$prefix$eol$sql"
                    }
                    $scriptPath = Get-ExportFilePath -Path $__boundPathValue -FilePath $__boundFilePathValue -Type sql -ServerName $outputFileName
                    $sql | Out-File -Encoding $Encoding -LiteralPath $scriptPath -Append:$Append -NoClobber:$NoClobber
                    $outputFileArray += $outputFileName
                    Get-ChildItem $scriptPath
                } else {
                    Write-Message -Level Verbose -Message "Adding to $outputFileName " -FunctionName Export-DbaServerRole -ModuleName "dbatools"
                    $sql | Out-File -Encoding $Encoding -LiteralPath $scriptPath -Append
                }
            } else {
                $sql
            }
        }
        }
        . Export-DbaServerRole
} $SqlInstance $SqlCredential $__batches $ScriptingOptionsObject $ServerRole $ExcludeServerRole $Path $FilePath $BatchSeparator $Encoding $ExcludeFixedRole $IncludeRoleMember $Passthru $NoClobber $Append $NoPrefix $EnableException $__pathBound $__batchSepBound $__scriptingBound $__boundPathValue $__boundFilePathValue $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1

""";
}
