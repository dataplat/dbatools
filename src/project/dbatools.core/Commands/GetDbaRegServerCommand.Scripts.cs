#nullable enable

namespace Dataplat.Dbatools.Commands;

// Hop script constants (the verbatim retired PS begin/process bodies) - split out per the repo 400-line file limit.
public sealed partial class GetDbaRegServerCommand
{

    // PS: the begin block VERBATIM, dot-sourced. Only edit is -FunctionName on the message calls.
    // The sentinel carries $defaults (the source-bug 5-column set - :180 overwrites the :175 set).
    // The two helper definitions ride verbatim here (unused in begin) and are recreated in process.
    private const string BeginScript = """
param($ResolveNetworkName, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($ResolveNetworkName, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    . {
        if ($ResolveNetworkName) {
            $defaults = 'ComputerName', 'FQDN', 'IPAddress', 'Name', 'ServerName', 'Group', 'Description', 'Source'
        }
        $defaults = 'Name', 'ServerName', 'Group', 'Description', 'Source'
        # thank you forever https://social.msdn.microsoft.com/Forums/sqlserver/en-US/57811d43-a2b9-4179-a97b-a9936ddb188e/how-to-retrieve-a-password-saved-by-sql-server?forum=sqltools
        function Unprotect-String([string] $base64String) {
            return [System.Text.Encoding]::Unicode.GetString([System.Security.Cryptography.ProtectedData]::Unprotect([System.Convert]::FromBase64String($base64String), $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser))
        }

        # Helper function to test if a name matches any of the provided regex patterns
        $matchesPattern = {
            param($name, $serverName, $patterns)
            if (!$patterns) { return $true }
            foreach ($pattern in $patterns) {
                if ($name -match $pattern -or $serverName -match $pattern) {
                    return $true
                }
            }
            return $false
        }
    }

    $__df = Get-Variable -Name defaults -Scope 0 -ErrorAction Ignore
    $__dfv = $null; if ($__df) { $__dfv = $__df.Value }
    @{ __getDbaRegServerBegin = @{ Defaults = $__dfv } }
} $ResolveNetworkName $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
    // PS: the process block VERBATIM, dot-sourced. Only edit is -FunctionName on message calls. The
    // two begin helpers are recreated first (begin's scope is gone); $defaults restores from the
    // begin sentinel; the DEF-007 SqlInstance/IncludeLocal defaults resolve here; and the caller's
    // real bound-parameter dictionary is substituted for $PSBoundParameters so its value reads at
    // :197/:232/:378/:379 stay faithful.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Name, $ServerName, $Pattern, $ExcludeServerName, $Group, $ExcludeGroup, $Id, $IncludeSelf, $ResolveNetworkName, $IncludeLocal, $EnableException, $__beginState, $__state, $__boundParameters, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [PSCredential]$SqlCredential, [string[]]$Name, [string[]]$ServerName, [string[]]$Pattern, [string[]]$ExcludeServerName, [string[]]$Group, [string[]]$ExcludeGroup, [int[]]$Id, $IncludeSelf, $ResolveNetworkName, $IncludeLocal, $EnableException, $__beginState, $__state, $__boundParameters, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

    # the caller's real bound parameters - the body reads $PSBoundParameters.X by VALUE at :197/:232/:378/:379
    $PSBoundParameters = $__boundParameters
    # the begin helpers, recreated (begin's scope does not reach this hop)
    function Unprotect-String([string] $base64String) {
        return [System.Text.Encoding]::Unicode.GetString([System.Security.Cryptography.ProtectedData]::Unprotect([System.Convert]::FromBase64String($base64String), $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser))
    }
    $matchesPattern = {
        param($name, $serverName, $patterns)
        if (!$patterns) { return $true }
        foreach ($pattern in $patterns) {
            if ($name -match $pattern -or $serverName -match $pattern) {
                return $true
            }
        }
        return $false
    }
    # begin's once-computed column set
    $defaults = $__beginState.Defaults
    # DEF-007 config defaults, matching the source parameter defaults
    if (-not $PSBoundParameters.ContainsKey('SqlInstance')) { $SqlInstance = Get-DbatoolsConfigValue -FullName 'commands.get-dbaregserver.defaultcms' }
    if (-not $PSBoundParameters.ContainsKey('IncludeLocal')) { $IncludeLocal = [bool](Get-DbatoolsConfigValue -FullName 'commands.get-dbaregserver.includelocal') }
    # $azureids (codex r1): initialized only inside the local-store path (:244), but read at :308 in
    # the unconditional "foreach ($server in $servers)" loop. On a record that does NOT take the
    # local-store path, the SOURCE (persistent process scope) reads a PREVIOUS record's $azureids;
    # a fresh hop scope would see $null. Carried with an Assigned flag so a first record - or a record
    # whose predecessors never took the path - leaves it undefined, exactly as the source does.
    if ($null -ne $__state -and $__state.AzureidsAssigned) { $azureids = $__state.Azureids }

    . {
        # W3-047 fix: this `. { }` dot-source runs as its own scriptblock invocation, so the
        # automatic $PSBoundParameters is RE-INITIALISED to empty here (measured 2026-07-20:
        # -Group read as empty inside this block). The source reads $PSBoundParameters directly in
        # process{} (populated); re-assert the caller's table INSIDE the block so the value reads
        # below (-SqlInstance/-IncludeLocal local-store gate at :~131, -Group/-ExcludeGroup filter
        # at :~277) see it - same dot-source-scope class as W2-151 New-DbaDbTable.
        $PSBoundParameters = $__boundParameters
        if (-not $PSBoundParameters.SqlInstance -and -not ($IsLinux -or $IsMacOs)) {
            $null = Get-ChildItem -Recurse "$(Get-DbatoolsPath -Name appdata)\Microsoft\*sql*" -Filter RegSrvr*.xml | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        }

        $servers = @()
        $serverstores = @()
        $serverToServerStore = @{ }
        foreach ($instance in $SqlInstance) {
            $serverstore = $null

            try {
                $serverstore = Get-DbaRegServerStore -SqlInstance $instance -SqlCredential $SqlCredential -EnableException
            } catch {
                Stop-Function -Message "Cannot access Central Management Server '$instance'." -ErrorRecord $_ -Continue -FunctionName Get-DbaRegServer
                continue
            }
            $serverstores += $serverstore

            if ($Group) {
                $groupservers = Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group -ExcludeGroup $ExcludeGroup
                if ($groupservers) {
                    $servers += $groupservers.GetDescendantRegisteredServers()
                }
            } else {
                $servers += ($serverstore.DatabaseEngineServerGroup.GetDescendantRegisteredServers())
                $serverstore.ServerConnection.Disconnect()
            }

            # save the $serverstore for later usage
            foreach ($server in $servers) {
                $serverToServerStore[$server] = $serverstore
            }
        }

        # Magic courtesy of Mathias Jessen and David Shifflet
        if (-not $PSBoundParameters.SqlInstance -or $PSBoundParameters.IncludeLocal) {
            $file = [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore]::LocalFileStore.DomainInstanceName
            if ($file) {
                if ((Test-Path -Path $file)) {
                    $class = [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServersStore]
                    $initMethod = $class.GetMethod('InitChildObjects', [Reflection.BindingFlags]'Static,NonPublic')
                    $store = ($initMethod.Invoke($null, @($file)))
                    # Local Reg Servers
                    foreach ($tempserver in $store.DatabaseEngineServerGroup.GetDescendantRegisteredServers()) {
                        $servers += $tempserver | Add-Member -Force -Name Source -Value "Local Server Groups" -MemberType NoteProperty -PassThru
                    }
                    # Azure Reg Servers
                    $azureids = @()
                    if ($store.AzureDataStudioConnectionStore.Groups) {
                        $adsconnection = Get-ADSConnection
                    }
                    foreach ($azuregroup in $store.AzureDataStudioConnectionStore.Groups) {
                        $groupname = $azuregroup.Name
                        if ($groupname -eq 'ROOT' -or $groupname -eq '') {
                            $groupname = $null
                        }
                        $tempgroup = New-Object Microsoft.SqlServer.Management.RegisteredServers.ServerGroup $groupname
                        $tempgroup.Description = $azuregroup.Description

                        foreach ($server in ($store.AzureDataStudioConnectionStore.Connections | Where-Object GroupId -eq $azuregroup.Id)) {
                            $azureids += [PSCustomObject]@{ id = $server.Id; group = $groupname }
                            $connname = $server.Options['connectionName']
                            if (-not $connname) {
                                $connname = $server.Options['server']
                            }
                            $adsconn = $adsconnection | Where-Object { $_.server -eq $server.Options['server'] -and -not $_.database }

                            $tempserver = New-Object Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer $tempgroup, $connname
                            $tempserver.Description = $server.Options['Description']
                            if ($adsconn.ConnectionString) {
                                $tempserver.ConnectionString = $adsconn.ConnectionString
                            }
                            # update read-only or problematic properties
                            $tempserver | Add-Member -Force -Name Source -Value "Azure Data Studio" -MemberType NoteProperty
                            $tempserver | Add-Member -Force -Name ServerName -Value $server.Options['server'] -MemberType NoteProperty
                            $tempserver | Add-Member -Force -Name Id -Value $server.Id -MemberType NoteProperty
                            $tempserver | Add-Member -Force -Name CredentialPersistenceType -Value 1 -MemberType NoteProperty
                            $tempserver | Add-Member -Force -Name ServerType -Value DatabaseEngine -MemberType NoteProperty
                            $servers += $tempserver
                        }
                    }
                }
            }
        }

        if ($Name) {
            Write-Message -Level Verbose -Message "Filtering by name for $name" -FunctionName Get-DbaRegServer -ModuleName "dbatools"
            $servers = $servers | Where-Object Name -in $Name
        }

        if ($ServerName) {
            Write-Message -Level Verbose -Message "Filtering by servername for $servername" -FunctionName Get-DbaRegServer -ModuleName "dbatools"
            $servers = $servers | Where-Object ServerName -in $ServerName
        }

        if ($Pattern) {
            Write-Message -Level Verbose -Message "Filtering by pattern for $Pattern" -FunctionName Get-DbaRegServer -ModuleName "dbatools"
            $servers = $servers | Where-Object { & $matchesPattern $_.Name $_.ServerName $Pattern }
        }

        if ($ExcludeServerName) {
            Write-Message -Level Verbose -Message "Excluding servers: $ExcludeServerName" -FunctionName Get-DbaRegServer -ModuleName "dbatools"
            $servers = $servers | Where-Object ServerName -notin $ExcludeServerName
        }

        if ($Id) {
            Write-Message -Level Verbose -Message "Filtering by id for $Id (1 = default/root)" -FunctionName Get-DbaRegServer -ModuleName "dbatools"
            $servers = $servers | Where-Object Id -in $Id
        }

        foreach ($server in $servers) {
            $az = $azureids | Where-Object Id -in $server.Id
            if ($az) {
                $groupname = $az.Group
            } else {
                $groupname = Get-RegServerGroupReverseParse $server
                if ($groupname -eq $server.Name) {
                    $groupname = $null
                } else {
                    $groupname = ($groupname).Split("\")
                    $groupname = $groupname[0 .. ($groupname.Count - 2)]
                    $groupname = ($groupname -join "\")
                }
            }
            # ugly way around it but it works
            $badform = "$($server.Name.Split("\")[0])\$($server.Name.Split("\")[0])"
            if ($groupname -eq $badform) {
                $groupname = $null
            }

            if ($ExcludeGroup -and ($groupname -in $ExcludeGroup)) {
                continue
            }

            if ($server.ConnectionStringWithEncryptedPassword) {
                $encodedconnstring = $connstring = $server.ConnectionStringWithEncryptedPassword
                if ($encodedconnstring -imatch 'password="?([^";]+)"?') {
                    $password = $Matches[1]
                    $password = Unprotect-String $password
                    $connstring = $encodedconnstring -ireplace 'password="?([^";]+)"?', "password=`"$password`""
                    Add-Member -Force -InputObject $server -MemberType NoteProperty -Name ConnectionString -Value $connstring
                    Add-Member -Force -InputObject $server -MemberType NoteProperty -Name SecureConnectionString -Value (ConvertTo-SecureString -String $connstring -AsPlainText -Force)
                }
            }

            if (-not $server.Source) {
                Add-Member -Force -InputObject $server -MemberType NoteProperty -Name Source -value "Central Management Servers"
            }

            if ( $null -ne $serverToServerStore[$server] ) {
                Add-Member -Force -InputObject $server -MemberType NoteProperty -Name ComputerName -value $serverToServerStore[$server].ComputerName
                Add-Member -Force -InputObject $server -MemberType NoteProperty -Name InstanceName -value $serverToServerStore[$server].InstanceName
                Add-Member -Force -InputObject $server -MemberType NoteProperty -Name SqlInstance -value $serverToServerStore[$server].SqlInstance
                Add-Member -Force -InputObject $server -MemberType NoteProperty -Name ParentServer -Value $serverToServerStore[$server].ParentServer
            }

            Add-Member -Force -InputObject $server -MemberType NoteProperty -Name Group -value $groupname
            Add-Member -Force -InputObject $server -MemberType NoteProperty -Name FQDN -Value $null
            Add-Member -Force -InputObject $server -MemberType NoteProperty -Name IPAddress -Value $null

            if ($ResolveNetworkName) {
                try {
                    $lookup = Resolve-DbaNetworkName $server.ServerName -Turbo
                    $server.ComputerName = $lookup.ComputerName
                    $server.FQDN = $lookup.FQDN
                    $server.IPAddress = $lookup.IPAddress
                } catch {
                    try {
                        $lookup = Resolve-DbaNetworkName $server.ServerName
                        $server.ComputerName = $lookup.ComputerName
                        $server.FQDN = $lookup.FQDN
                        $server.IPAddress = $lookup.IPAddress
                    } catch {
                        # here to avoid an empty catch
                        $null = 1
                    }
                }
            }

            # this is a bit dirty and should be addressed by someone who better knows recursion and regex
            if ($server.Source -ne "Central Management Servers") {
                if ($PSBoundParameters.Group -and $groupname -notin $PSBoundParameters.Group) { continue }
                if ($PSBoundParameters.ExcludeGroup -and $groupname -in $PSBoundParameters.ExcludeGroup) { continue }
            }

            Add-Member -Force -InputObject $server -MemberType ScriptMethod -Name ToString -Value { $this.ServerName }
            Select-DefaultView -InputObject $server -Property $defaults
        }

        if ($IncludeSelf -and $serverstores) {
            foreach ($currentServerStore in $serverstores) {
                Write-Message -Level Verbose -Message "Adding CMS instance" -FunctionName Get-DbaRegServer -ModuleName "dbatools"
                $self = [PSCustomObject]@{
                    Name         = "CMS Instance"
                    ServerName   = $currentServerStore.SqlInstance
                    Group        = $null
                    Description  = $null
                    Source       = "Central Management Servers"
                    ComputerName = $currentServerStore.ComputerName
                    InstanceName = $currentServerStore.InstanceName
                    SqlInstance  = $currentServerStore.SqlInstance
                    ParentServer = $currentServerStore.ParentServer
                    FQDN         = $null
                    IPAddress    = $null
                }
                $self | Add-Member -MemberType ScriptMethod -Name ToString -Value { $this.ServerName } -Force
                Select-DefaultView -InputObject $self -Property $defaults
            }
        }
    }

    $__az = Get-Variable -Name azureids -Scope 0 -ErrorAction Ignore
    $__azv = $null; if ($__az) { $__azv = $__az.Value }
    @{ __getDbaRegServerProcess = @{ AzureidsAssigned = [bool]$__az; Azureids = $__azv } }
} $SqlInstance $SqlCredential $Name $ServerName $Pattern $ExcludeServerName $Group $ExcludeGroup $Id $IncludeSelf $ResolveNetworkName $IncludeLocal $EnableException $__beginState $__state $__boundParameters $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
