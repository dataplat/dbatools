function Import-DbaRegServer {
    <#
    .SYNOPSIS
        Imports registered servers and server groups into SQL Server Central Management Server from XML files, other CMS instances, or custom objects

    .DESCRIPTION
        Imports registered servers and server groups into a SQL Server Central Management Server (CMS) from multiple sources including exported XML files, other CMS instances, or custom objects like CSVs. The function automatically creates missing server groups during import and supports importing to specific group locations within the CMS hierarchy. This is essential for migrating CMS configurations between environments, consolidating server inventories from multiple sources, or bulk-loading server lists into a new CMS setup.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Group
        Specifies the target group within the CMS hierarchy where servers will be imported. Accepts group paths using backslash notation like "hr\Seattle" or ServerGroup objects from Get-DbaRegServerGroup.
        Use this when you need to organize imported servers into specific groups rather than importing to the root level.

    .PARAMETER Path
        Specifies the file path to XML files containing exported registered server configurations from SQL Server Management Studio or Export-DbaRegServer.
        Use this when migrating CMS configurations between environments or restoring server lists from backup exports.

    .PARAMETER InputObject
        Accepts registered server objects, server group objects, or custom objects like CSV data for bulk import operations. Supports piping from Get-DbaRegServer and Get-DbaRegServerGroup cmdlets.
        When importing from CSV or custom objects, ServerName column is required while Name, Description, and Group columns are optional. Use this for consolidating servers from multiple CMS instances or bulk-loading server inventories.

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
        https://dbatools.io/Import-DbaRegServer

    .OUTPUTS
        Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer

        Returns one RegisteredServer object for each server successfully imported into the target Central Management Server (CMS). When importing from XML files, returns only newly imported servers (servers that did not exist before the import operation).

        Default display properties (via Select-DefaultView):
        - Name: The display name of the registered server as shown in SSMS Registered Servers
        - ServerName: The actual SQL Server connection string (computer name, IP address, or instance name)
        - Group: The CMS group path (hierarchical, using backslash separators) or null for root-level servers
        - Description: Text description of the registered server
        - Source: Source location of the registration - "Central Management Servers", "Local Server Groups", or "Azure Data Studio"

        Additional properties available from the RegisteredServer object (via Select-Object *):
        - ComputerName: NetBIOS computer name of the CMS instance
        - InstanceName: The SQL Server instance name of the CMS
        - SqlInstance: The full SQL Server instance name of the CMS
        - ParentServer: The parent CMS instance name
        - ConnectionString: The connection string with decrypted password if available
        - SecureConnectionString: The connection string as a SecureString object if password was decrypted
        - Id: Internal identifier for the registered server
        - ServerType: Type of server (DatabaseEngine, AnalysisServices, ReportingServices, etc.)
        - CredentialPersistenceType: Whether credentials are stored
        - Urn: The Uniform Resource Name (URN) for the registered server object

        All properties from the base RegisteredServer SMO object are accessible using Select-Object *.

    .EXAMPLE
        PS C:\> Import-DbaRegServer -SqlInstance sql2012 -Path C:\temp\corp-regservers.xml

        Imports C:\temp\corp-regservers.xml to the CMS on sql2012

    .EXAMPLE
        PS C:\> Import-DbaRegServer -SqlInstance sql2008 -Group hr\Seattle -Path C:\temp\Seattle.xml

        Imports C:\temp\Seattle.xml to Seattle subgroup within the hr group on sql2008

    .EXAMPLE
        PS C:\> Get-DbaRegServer -SqlInstance sql2008, sql2012 | Import-DbaRegServer -SqlInstance sql2017

        Imports all registered servers from sql2008 and sql2012 to sql2017

    .EXAMPLE
        PS C:\> Get-DbaRegServerGroup -SqlInstance sql2008 -Group hr\Seattle | Import-DbaRegServer -SqlInstance sql2017 -Group Seattle

        Imports all registered servers from the hr\Seattle group on sql2008 to the Seattle group on sql2017

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("FullName")]
        [string[]]$Path,
        [parameter(ValueFromPipeline)]
        [object[]]$InputObject,
        [object]$Group,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            # Prep to import from file
            if ((Test-Bound -ParameterName Path)) {
                $InputObject += Get-ChildItem -Path $Path
            }
            if ((Test-Bound -ParameterName Group) -and (Test-Bound -Not -ParameterName Path)) {
                if ($Group -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]) {
                    $groupobject = $Group
                } else {
                    $groupobject = Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group
                }
                if (-not $groupobject) {
                    Stop-Function -Message "Group $Group cannot be found on $instance" -Target $instance -Continue
                }
            }

            foreach ($object in $InputObject) {
                if ($object -is [Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer]) {

                    $groupexists = Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $object.Parent.Name
                    if (-not $groupexists) {
                        $groupexists = Add-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Name $object.Parent.Name
                    }
                    Add-DbaRegServer -SqlInstance $instance -SqlCredential $SqlCredential -Name $object.Name -ServerName $object.ServerName -Description $object.Description -Group $groupexists
                } elseif ($object -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]) {
                    foreach ($regserver in $object.RegisteredServers) {
                        $groupexists = Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $regserver.Parent.Name
                        if (-not $groupexists) {
                            $groupexists = Add-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Name $regserver.Parent.Name
                        }
                        Add-DbaRegServer -SqlInstance $instance -SqlCredential $SqlCredential -Name $regserver.Name -ServerName $regserver.ServerName -Description $regserver.Description -Group $groupexists
                    }
                } elseif ($object -is [System.IO.FileInfo]) {
                    if ((Test-Bound -ParameterName Group)) {
                        if ($Group -is [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]) {
                            $reggroups = $Group
                        } else {
                            $reggroups = Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Group $Group
                        }
                    } else {
                        $reggroups = Get-DbaRegServerGroup -SqlInstance $instance -SqlCredential $SqlCredential -Id 1
                    }

                    foreach ($file in $object) {
                        if (-not (Test-Path -Path $file)) {
                            Stop-Function -Message "$file cannot be found" -Target $file -Continue
                        }

                        foreach ($reggroup in $reggroups) {
                            try {
                                Write-Message -Level Verbose -Message "Importing $file to $($reggroup.Name) on $instance"
                                $urnlist = $reggroup.RegisteredServers.Urn.Value
                                $reggroup.Import($file.FullName)
                                Get-DbaRegServer -SqlInstance $instance -SqlCredential $SqlCredential | Where-Object { $_.Urn.Value -notin $urnlist }
                            } catch {
                                Stop-Function -Message "Failure attempting to import $file to $instance" -ErrorRecord $_ -Continue
                            }
                        }
                    }
                } else {
                    if (-not $object.ServerName) {
                        Stop-Function -Message "Property 'ServerName' not found in InputObject. No servers added." -Continue
                    }

                    if (-not (Test-Bound -ParameterName Group)) {
                        Add-DbaRegServer -SqlInstance $instance -SqlCredential $SqlCredential -Name $object.Name -ServerName $object.ServerName -Description $object.Description -Group $object.Group
                    } else {
                        Add-DbaRegServer -SqlInstance $instance -SqlCredential $SqlCredential -Name $object.Name -ServerName $object.ServerName -Description $object.Description -Group $groupobject
                    }
                }
            }
        }
    }
}