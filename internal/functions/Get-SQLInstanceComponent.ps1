function Get-SQLInstanceComponent {
    <#
    .SYNOPSIS
        Retrieves SQL server information from a local or remote servers.
    .DESCRIPTION
        Retrieves SQL server information from a local or remote servers. Pulls all instances from a SQL server and
        detects if in a cluster or not.
    .PARAMETER ComputerName
        Local or remote systems to query for SQL information.
    .NOTES
        Tags: Install, Patching, SP, CU, Instance
        Author: Kirill Kravtsov (@nvarscar) https://nvarscar.wordpress.com/

        Based on https://github.com/adbertram/PSSqlUpdater
        The majority of this function was created by Boe Prox.
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
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Computer', 'DNSHostName', 'IPAddress')]
        [DbaInstanceParameter[]]$ComputerName = $Env:COMPUTERNAME,
        [ValidateSet('SSDS', 'SSAS', 'SSRS')]
        [string[]]$Component = @('SSDS', 'SSAS', 'SSRS'),
        [pscredential]$Credential
    )

    begin {

        $regScript = {
            Param (
                $ComponentObject
            )
            $Component = $ComponentObject.Component
            $componentNameMap = @(
                [pscustomobject]@{
                    ComponentName = 'SSAS';
                    DisplayName   = 'Analysis Services';
                    RegKeyName    = "OLAP";
                },
                [pscustomobject]@{
                    ComponentName = 'SSDS';
                    DisplayName   = 'Database Engine';
                    RegKeyName    = 'SQL';
                },
                [pscustomobject]@{
                    ComponentName = 'SSRS';
                    DisplayName   = 'Reporting Services';
                    RegKeyName    = 'RS';
                }
            );

            function Get-SQLInstanceDetail {
                <#
                    .SYNOPSIS
                        The majority of this function was created by Boe Prox.
                #>
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
                        $log = @()
                        $nodes = New-Object System.Collections.ArrayList;
                        $clusterName = $null;
                        $isCluster = $false;
                        $instanceValue = $regKey.GetValue($sqlInstance);
                        $log += "Working with $regPath\$instanceValue on $computer"
                        $instanceReg = $reg.OpenSubKey("$regPath\\$instanceValue");
                        if ($instanceReg.GetSubKeyNames() -contains 'Cluster') {
                            $isCluster = $true;
                            $instanceRegCluster = $instanceReg.OpenSubKey('Cluster');
                            $clusterName = $instanceRegCluster.GetValue('ClusterName');
                            #Write-Message -Level Verbose -Message "Getting cluster node names";
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

                        #region Get resume value
                        try {
                            $resume = [bool][int]$instanceRegSetup.GetValue("Resume");
                        } catch {
                            $resume = $false;
                        }
                        #endregion Get resume value

                        #region Get SQL version
                        $version = $null
                        try {
                            $versionHash = @{
                                '11' = 'SQLServer2012'
                                '12' = 'SQLServer2014'
                                '13' = 'SQLServer2016'
                                '14' = 'SQL2017'
                                '15' = 'SQL2019'
                            }
                            $version = $instanceRegSetup.GetValue("Version");
                            $log += "Found version $version"
                            if ($patchVersion = $instanceRegSetup.GetValue("PatchLevel")) {
                                $log += "Using patch version $patchVersion over $version"
                                $version = $patchVersion
                            }
                            # if patch version is not available - use global reg node to extract the latest patch
                            $majorVersion = $version.Split('.')[0]
                            if (!$patchVersion -and $majorVersion -and $versionHash[$majorVersion]) {
                                $verKey = $reg.OpenSubKey("SOFTWARE\\Microsoft\\Microsoft SQL Server\\$($majorVersion)0\\$($versionHash[$majorVersion])\\CurrentVersion")
                                $version = $verKey.GetValue('Version')
                                $log += "New version from the CurrentVersion key: $version"
                            }
                        } catch {
                            $log += "Failed to read one of the reg keys, found version $version so far"
                        }
                        #endregion Get SQL version

                        #region Get exe version
                        try {
                            # attempt to recover a real version of a sqlservr.exe by getting file properties from a remote machine
                            # not sure how to support SSRS/SSAS, as SSDS is the only one that has binary path in the Setup node
                            if ($binRoot = $instanceRegSetup.GetValue("SQLBinRoot")) {
                                $fileVersion = (Get-Item -Path (Join-Path $binRoot "sqlservr.exe") -ErrorAction Stop).VersionInfo.ProductVersion
                                if ($fileVersion) {
                                    $version = $fileVersion
                                    $log += "New version from the binary file: $version"
                                }
                            }
                        } catch {
                            $log += "Failed to get exe version, leaving $version as is"
                        }
                        #endregion Get exe version

                        #endregion Gather additional information about SQL instance

                        #region Generate return object
                        [pscustomobject]@{
                            ComputerName  = $computer.ToUpper();
                            InstanceName  = $sqlInstance;
                            InstanceID    = $instanceValue;
                            InstanceDir   = $instanceDir;
                            Edition       = $edition;
                            Version       = $version;
                            Caption       = {
                                switch -regex ($version) {
                                    "^11" { "SQL Server 2012"; break }
                                    "^10\.5" { "SQL Server 2008 R2"; break }
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
                            Log           = $log
                            Resume        = $resume
                        }
                        #endregion Generate return object
                    }
                    #endregion Process each instance
                }
            }
            $reg = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Default')
            $baseKeys = "SOFTWARE\\Microsoft\\Microsoft SQL Server", "SOFTWARE\\Wow6432Node\\Microsoft\\Microsoft SQL Server";
            if ($reg.OpenSubKey($baseKeys[0])) {
                $regPath = $baseKeys[0];
            } elseif ($reg.OpenSubKey($baseKeys[1])) {
                $regPath = $baseKeys[1];
            } else {
                throw "Failed to find any regkeys on $env:computername"
            }

            $computer = $Env:COMPUTERNAME

            $regKey = $reg.OpenSubKey("$regPath");
            if ($regKey.GetSubKeyNames() -contains "Instance Names") {
                foreach ($componentName in $Component) {
                    $componentRegKeyName = $componentNameMap |
                        Where-Object { $_.ComponentName -eq $componentName } |
                        Select-Object -ExpandProperty RegKeyName;
                    $regKey = $reg.OpenSubKey("$regPath\\Instance Names\\{0}" -f $componentRegKeyName);
                    if ($regKey) {
                        foreach ($regValueName in $regKey.GetValueNames()) {
                            if ($componentRegKeyName -eq 'RS' -and $regValueName -eq 'PBIRS') { continue } #filtering out Power BI - not supported
                            if ($componentRegKeyName -eq 'RS' -and $regValueName -eq 'SSRS') { continue }  #filtering out SSRS2017+ - not supported
                            $result = Get-SQLInstanceDetail -RegPath $regPath -Reg $reg -RegKey $regKey -Instance $regValueName;
                            $result | Add-Member -Type NoteProperty -Name InstanceType -Value ($componentNameMap | Where-Object { $_.ComponentName -eq $componentName }).DisplayName -PassThru
                        }
                    }
                }
            } elseif ($regKey.GetValueNames() -contains 'InstalledInstances') {
                $isCluster = $false;
                $regKey.GetValue('InstalledInstances') | ForEach-Object {
                    Get-SQLInstanceDetail -RegPath $regPath -Reg $reg -RegKey $regKey -Instance $_
                };
            } else {
                throw "Failed to find any instance names on $env:computername"
            }
        }
    }
    process {
        foreach ($computer in $ComputerName) {
            $arguments = @{ Component = $Component }
            $results = Invoke-Command2 -ComputerName $computer -ScriptBlock $regScript -Credential $Credential -ErrorAction Stop -Raw -ArgumentList $arguments -RequiredPSVersion 3.0

            # Log is stored in the log property, pile it all into the debug log
            foreach ($logEntry in $results.Log) {
                Write-Message -Level Debug -Message $logEntry
            }
            foreach ($result in $results) {
                # If version is unknown that component should be excluded, otherwise it would fail on conversion. We have no use for versionless components anyways.
                if (-Not $result.Version) {
                    Write-Message -Level Warning -Message "Component $($result.InstanceName) on $($result.ComputerName) has an unknown version and was ommitted from the instance list"
                    continue
                }
                # Replace first decimal of the minor build with a 0, since we're using build numbers here
                # Refer to https://sqlserverbuilds.blogspot.com/
                Write-Message -Level Debug -Message "Converting version $($result.Version) to [version]"
                $newVersion = New-Object -TypeName System.Version -ArgumentList ([string]$result.Version)
                $newVersion = New-Object -TypeName System.Version -ArgumentList ($newVersion.Major , ($newVersion.Minor - $newVersion.Minor % 10), $newVersion.Build)
                Write-Message -Level Debug -Message "Converted version $($result.Version) to $newVersion"
                # Find a proper build reference and replace Version property
                $result.Version = Get-DbaBuildReference -Build $newVersion -EnableException
                $result | Select-Object -ExcludeProperty Log
            }
        }
    }
}