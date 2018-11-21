function Get-SQLInstanceComponent {
    <#
    .SYNOPSIS
        Retrieves SQL server information from a local or remote servers. The majority of this function was created by
        Boe Prox.
    .DESCRIPTION
        Retrieves SQL server information from a local or remote servers. Pulls all instances from a SQL server and
        detects if in a cluster or not.
    .PARAMETER ComputerName
        Local or remote systems to query for SQL information.
    .NOTES
        Name: Get-SQLInstance
        Author: Boe Prox
        DateCreated: 07 SEPT 2013
    .EXAMPLE
        Get-SQLInstanceComponent -ComputerName SQL01 -Component SSDS
        ComputerName  : BDT005-BT-SQL
        InstanceType  : Database Engine
        InstanceName  : MSSQLSERVER
        InstanceID    : MSSQL11.MSSQLSERVER
        Edition       : Enterprise Edition
        Version       : 11.1.3000.0
        Caption       : SQL Server 2012
        IsCluster     : False
        IsClusterNode : False
        ClusterName   :
        ClusterNodes  : {}
        FullName      : BDT005-BT-SQL
        Description
        -----------
        Retrieves the SQL instance information from SQL01 for component type SSDS (Database Engine).
    .EXAMPLE
        Get-SQLInstanceComponent -ComputerName SQL01
        ComputerName  : BDT005-BT-SQL
        InstanceType  : Analysis Services
        InstanceName  : MSSQLSERVER
        InstanceID    : MSAS11.MSSQLSERVER
        Edition       : Enterprise Edition
        Version       : 11.1.3000.0
        Caption       : SQL Server 2012
        IsCluster     : False
        IsClusterNode : False
        ClusterName   :
        ClusterNodes  : {}
        FullName      : BDT005-BT-SQL
        ComputerName  : BDT005-BT-SQL
        InstanceType  : Reporting Services
        InstanceName  : MSSQLSERVER
        InstanceID    : MSRS11.MSSQLSERVER
        Edition       : Enterprise Edition
        Version       : 11.1.3000.0
        Caption       : SQL Server 2012
        IsCluster     : False
        IsClusterNode : False
        ClusterName   :
        ClusterNodes  : {}
        FullName      : BDT005-BT-SQL
        Description
        -----------
        Retrieves the SQL instance information from SQL01 for all component types (SSAS, SSDS, SSRS).
#>

    [CmdletBinding()]
    param
    (
        [Parameter(ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('__Server', 'DNSHostName', 'IPAddress')]
        [string[]]$ComputerName = $Env:COMPUTERNAME,

        [Parameter()]
        [ValidateSet('SSDS', 'SSAS', 'SSRS')]
        [string[]]$Component = @('SSDS', 'SSAS', 'SSRS')
    )

    begin {
        function Get-SQLInstanceDetail {
            <#
                .SYNOPSIS
                    The majority of this function was created by Boe Prox.

                .EXAMPLE
                    PS> $functionName

                .PARAMETER parameter
                    A mandatoryorOptional paramType parameter representing

            #>
            [CmdletBinding()]
            param
            (
                [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
                [string[]]$Instance,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [Microsoft.Win32.RegistryKey]$RegKey,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [Microsoft.Win32.RegistryKey]$reg,

                [Parameter(Mandatory)]
                [ValidateNotNullOrEmpty()]
                [string]$RegPath
            )
            process {
                #region Process each instance
                foreach ($sqlInstance in $Instance) {
                    $nodes = New-Object System.Collections.ArrayList;
                    $clusterName = $null;
                    $isCluster = $false;
                    $instanceValue = $regKey.GetValue($sqlInstance);
                    $instanceReg = $reg.OpenSubKey("$regPath\\$instanceValue");
                    if ($instanceReg.GetSubKeyNames() -contains 'Cluster')
                    {
                        $isCluster = $true;
                        $instanceRegCluster = $instanceReg.OpenSubKey('Cluster');
                        $clusterName = $instanceRegCluster.GetValue('ClusterName');
                        Write-Verbose -Message "Getting cluster node names";
                        $clusterReg = $reg.OpenSubKey("Cluster\\Nodes");
                        $clusterNodes = $clusterReg.GetSubKeyNames();
                        if ($clusterNodes) {
                            foreach ($clusterNode in $clusterNodes) {
                                $null = $nodes.Add($clusterReg.OpenSubKey($clusterNode).GetValue("NodeName").ToUpper());
                            }
                        }
                    }

                    #region Gather additional information about SQL instance
                    $instanceRegSetup = $instanceReg.OpenSubKey("Setup")

                    #region Get SQL instance directory
                    try {
                        $instanceDir = $instanceRegSetup.GetValue("SqlProgramDir");
                        if (([System.IO.Path]::GetPathRoot($instanceDir) -ne $instanceDir) -and $instanceDir.EndsWith("\")) {
                            $instanceDir = $instanceDir.Substring(0, $instanceDir.Length - 1);
                        }
                    } catch {
                        $instanceDir = $null;
                    }
                    #endregion Get SQL instance directory

                    #region Get SQL edition
                    try {
                        $edition = $instanceRegSetup.GetValue("Edition");
                    } catch {
                        $edition = $null;
                    }
                    #endregion Get SQL edition

                    #region Get SQL version
                    try {

                        $version = $instanceRegSetup.GetValue("Version");
                        if ($version.Split('.')[0] -eq '11') {
                            $verKey = $reg.OpenSubKey('SOFTWARE\\Microsoft\\Microsoft SQL Server\\110\\SQLServer2012\\CurrentVersion')
                            $version = $verKey.GetValue('Version')
                        } elseif ($version.Split('.')[0] -eq '12') {
                            $verKey = $reg.OpenSubKey('SOFTWARE\\Microsoft\\Microsoft SQL Server\\120\\SQLServer2014\\CurrentVersion')
                            $version = $verKey.GetValue('Version')
                        }
                    } catch {
                        $version = $null;
                    }
                    #endregion Get SQL version

                    #endregion Gather additional information about SQL instance

                    #region Generate return object
                    [pscustomobject]@{
                        ComputerName  = $computer.ToUpper();
                        InstanceType  = {
                            $componentNameMap | Where-Object { $_.ComponentName -eq $componentName } |
                                Select-Object -ExpandProperty DisplayName
                        }.InvokeReturnAsIs();
                        InstanceName  = $sqlInstance;
                        InstanceID    = $instanceValue;
                        InstanceDir   = $instanceDir;
                        Edition       = $edition;
                        Version       = $version;
                        Caption       = {
                            switch -regex ($version) {
                                "^11" { "SQL Server 2012"; break }
                                "^10\.5"	{ "SQL Server 2008 R2"; break }
                                "^10" { "SQL Server 2008"; break }
                                "^9" { "SQL Server 2005"; break }
                                "^8" { "SQL Server 2000"; break }
                                default { "Unknown"; }
                            }
                        }.InvokeReturnAsIs();
                        IsCluster     = $isCluster;
                        IsClusterNode = ($nodes -contains $computer);
                        ClusterName   = $clusterName;
                        ClusterNodes  = ($nodes -ne $computer);
                        FullName      = {
                            if ($sqlInstance -eq "MSSQLSERVER") {
                                $computer.ToUpper();
                            } else {
                                "$($computer.ToUpper())\$($sqlInstance)";
                            }
                        }.InvokeReturnAsIs();
                    }
                    #endregion Generate return object
                }
                #endregion Process each instance
            }
        }
        $componentNameMap = @(
            [pscustomobject]@{
                ComponentName	= 'SSAS';
                DisplayName   = 'Analysis Services';
                RegKeyName    = "OLAP";
            },
            [pscustomobject]@{
                ComponentName	= 'SSDS';
                DisplayName   = 'Database Engine';
                RegKeyName    = 'SQL';
            },
            [pscustomobject]@{
                ComponentName	= 'SSRS';
                DisplayName   = 'Reporting Services';
                RegKeyName    = 'RS';
            }
        );
    }

    process {
        foreach ($computer in $ComputerName) {
            try {
                #region Connect to the specified computer and open the registry key
                $reg = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey('LocalMachine', $computer);
                $baseKeys = "SOFTWARE\\Microsoft\\Microsoft SQL Server", "SOFTWARE\\Wow6432Node\\Microsoft\\Microsoft SQL Server";
                if ($reg.OpenSubKey($baseKeys[0])) {
                    $regPath = $baseKeys[0];
                } elseif ($reg.OpenSubKey($baseKeys[1])) {
                    $regPath = $baseKeys[1];
                } else {
                    continue;
                }
                #endregion Connect to the specified computer and open the registry key

                # Shorten the computer name if a FQDN was specified.
                $computer = $computer -replace '(.*?)\..+', '$1';

                $regKey = $reg.OpenSubKey("$regPath");
                if ($regKey.GetSubKeyNames() -contains "Instance Names") {
                    foreach ($componentName in $Component) {
                        $componentRegKeyName = $componentNameMap |
                            Where-Object { $_.ComponentName -eq $componentName } |
                            Select-Object -ExpandProperty RegKeyName;
                        $regKey = $reg.OpenSubKey("$regPath\\Instance Names\\{0}" -f $componentRegKeyName);
                        if ($regKey) {
                            foreach ($regValueName in $regKey.GetValueNames()) {
                                Get-SQLInstanceDetail -RegPath $regPath -Reg $reg -RegKey $regKey -Instance $regValueName;
                            }
                        }
                    }
                } elseif ($regKey.GetValueNames() -contains 'InstalledInstances') {
                    $isCluster = $false;
                    $regKey.GetValue('InstalledInstances') | ForEach-Object {
                        Get-SQLInstanceDetail -RegPath $regPath -Reg $reg -RegKey $regKey -Instance $_;
                    };
                } else {
                    continue;
                }
            } catch {
                Stop-Function -Message "Failed to get instance components from $computer" -ErrorRecord $_ -Continue
            }
        }
    }
}
