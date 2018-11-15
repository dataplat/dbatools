function Install-DbaInstance {
    <#
    .SYNOPSIS

        This function will help you to quickly install a SQL Server instance.

    .DESCRIPTION

        This function will help you to quickly install a SQL Server instance.

        The number of TempDB files will be set to the number of cores with a maximum of eight.

        The perform volume maintenance right can be granted to the SQL Server account. if you happen to activate this in an environment where you are not allowed to do this,
        please revert that operation by removing the right from the local security policy (secpol.msc).

        You will see a screen with the users available on your machine. There you can choose the user that will act as Service Account for your SQL Server Install. This
        implies that the user has been created beforehand.

        Note that the dowloaded installation file must be unzipped or an ISO has to be mounted. This will not be executed from this script. This function offers the possibility
        to execute an autosearch for the installation files. But you can just browse to the correct file if you like.
    
    .PARAMETER SqlInstance
        The target SQL Server name

    .PARAMETER SqlCredential
        This parameter allows you to securely provide the password for the sa account when using mixed mode authentication.
    
    .PARAMETER Credential
        Used when executing installs against remote servers
  
    .PARAMETER ConfigurationFile
        The path to the configuration.ini. If one is not supplied, one will be generated.
    
    .PARAMETER Version
        Version will hold the SQL Server version you wish to install. The variable will support autocomplete

    .PARAMETER Edition
        Edition will hold the different basic editions of SQL Server: Express, Standard, Enterprise and Developer. The variable will support autocomplete

    .PARAMETER Role
        Role Will hold the option to install all features with defaults. Version is still mandatory. if no Edition is selected, it will default to Express!

    .PARAMETER Optional
        StatsandML will hold the R and Python choices. The variable will support autocomplete. There will be a check on version; this parameter will revert to NULL if the version is below 2016

    .PARAMETER Appvolume
        ProgramPath will hold the volume letter of the application disc. if left empty, it will default to C, unless there is a drive named like App

    .PARAMETER DataPath
        DataPath will hold the volume letter of the Data disc. if left empty, it will default to C, unless there is a drive named like Data

    .PARAMETER LogPath
        LogPath will hold the volume letter of the Log disc. if left empty, it will default to C, unless there is a drive named like Log

    .PARAMETER TempPath
        TempPath will hold the volume letter of the Temp disc. if left empty, it will default to C, unless there is a drive named like Temp

    .PARAMETER BackupPath
        BackupPath will hold the volume letter of the Backup disc. if left empty, it will default to C, unless there is a drive named like Backup

    .PARAMETER BinaryPath
        BinaryPath will hold the driveletter and subsequent folders (if any) of your installation media. The input must point to the location where the
        setup.exe is located.

    .PARAMETER PerformPathMaintenance
        PerformPathMaintenance will set the policy for grant or deny this right to the SQL Server service account.

    .PARAMETER SaveConfiguration
        SaveConfiguration will prompt you for a file location to save the new config file. Otherwise it will only be saved in the PowerShell bin directory.

    .PARAMETER AuthenticationMode
        AuthenticationMode will prompt you if you want mixed mode authentication or just Windows AD authentication. With Mixed Mode, you will be prompted for the SA password.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Install
        Author: Reitse Eskens (@2meterDBA)
        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT
    
    .Example
        C:\PS> Install-DbaInstance -Role AllFeaturesWithDefaults

        This will install a default SQL Server instance and run the installation with the default settings. Automatically generates configuration.ini

    .Example
        C:\PS> Install-DbaInstance -SqlInstance sql2017\sqlexpress, server01 -Version 2017 -Role AllFeaturesWithDefaults

        This will install a named SQL Server instance named sqlexpress on the remote machine, sql2017, and a default instance on server01. Automatically generates configuration.ini
    
    .Example
        C:\PS> Install-DbaInstance -SqlInstance sql2017 -ConfigurationFile C:\temp\configuration.ini

        This will install a default named SQL Server instance on the remote machine, sql2017 and use the local configuration.ini
    
    .Example
        C:\PS> Install-DbaInstance -ProgramPath  G

        This will run the installation with default setting apart from the application volume, this will be redirected to the G drive.

    .Example
        C:\PS> Install-DbaInstance -Version 2016 -ProgramPath D -DataPath E -LogPath L -PerformPathMaintenance -AdminAccount MyDomain\SvcSqlServer

        This will install SQL Server 2016 on the D drive, the data on E, the logs on L and the other files on the autodetected drives. The perform volume maintenance
        right is granted and the domain account SvcSqlServer will be used as the service account for SqlServer.

       #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance = $env:COMPUTERNAME,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [parameter(ValueFromPipeline)]
        [Alias("FilePath")]
        [object]$ConfigurationFile,
        [string]$BinaryPath,
        [ValidateSet("2008", "2008R2", "2012", "2014", "2016", "2017", "2019")]
        [string]$Version,
        [ValidateSet("Express", "Standard", "Enterprise", "Developer")]
        [string]$Edition = "Express",
        [ValidateSet("AllFeaturesWithDefaults", "Custom")]
        [string]$Role,
        [ValidateSet("Python", "R", "Python and R")]
        [string]$Optional,
        [ValidateSet("Windows", "Mixed")]
        [string]$AuthenticationMode = "Windows",
        [string]$ProgramPath,
        [string]$DataPath,
        [string]$LogPath,
        [string]$TempPath,
        [string]$BackupPath,
        [switch]$PerformPathMaintenance,
        [switch]$SaveConfiguration,
        [switch]$EnableException
    )
    process {
        if (-not $ConfigurationFile -and -not $Version) {
            Stop-Function -Message "You must specify either ConfigurationFile or Version"
            return
        }
        
        if ($null -eq $Role -or $Role -eq "AllFeaturesWithDefaults") {
            #Reminder to check which paramters should be set to run a default.
        }
        
        if ($null -eq $Role -or $Role -eq "AllFeaturesWithDefaults") {
            #Reminder to check which paramters should be set to run a default.
        }
        
        # Check if the edition of SQL Server supports Python and R. Introduced in SQL 2016, it should not be allowed in earlier installations.
        if ($Optional -and $Version -notin "2016", "2017", "2019") {
            #Reminder to check on all faulty combinations that might be possible
            Stop-Function -Message "$Optional not available in $version"
            return
        }
        
        # auto generate a random 50 character password if mixed is chosen and a credential is not provided
        if ($AuthenticationMode -eq "Mixed" -and -not $SqlCredential) {
            $secpasswd = ConvertTo-SecureString $(([char[]]([char]33 .. [char]95) + ([char[]]([char]97 .. [char]126)) + 0 .. 9 | Sort-Object {
                        Get-Random
                    })[0 .. 40] -join '') -AsPlainText -Force
            $SqlCredential = New-Object System.Management.Automation.PSCredential ("sa", $secpasswd)
        }
        
        # turn the configuration file into an object so we can access it various ways
        if ($ConfigurationFile) {
            try {
                $null = Test-Path -Path $ConfigurationFile -ErrorAction Stop
                $ConfigurationFile = Get-ChildItem -Path $ConfigurationFile
            } catch {
                Stop-Function -Message "Failure" -ErrorRecord $_
                return
            }    
        }
        
        foreach ($instance in $SqlInstance) {
            # Get the installation folder of SQL Server. if the user didn't choose a specific folder, the autosearch will commence. It will take some time!
            # To limit the number of results, the search exludes the Windows, program files, program data and users directories.
            # If the user added the folder where the installation disc or files are located, the input is somewhat sanitized to allow multiple sorts of entry.
            # The user is expected to add the complete folder structure!
            
            if (-not (Test-Bound -ParameterName Path)) {
                Write-Message -Level Verbose -Message "No Setup directory found. Switching to autosearch"
                
                $setupfile = Get-CimInstance -ClassName cim_datafile -Filter "Extension = 'EXE'" |
                Where-Object {
                    ($_.Name.ToUpper().Contains('SETUP') -and $_.Name -notlike '*users*' -and $_.Name -notlike '*Program*' -and $_.Name -notlike '*Windows*')
                } |
                Select-Object -Property @{
                    Label   = "FileLocation"; Expression = {
                        $_.Name
                    }
                } |
                Out-GridView -Title 'Please select the correct folder with the SQL Server installation Media' -PassThru |
                Select-Object -ExpandProperty FileLocation
                
                Write-Message -Level Verbose -Message 'Selected Setup: ' + $setupfile
            } else {
                $setupfile = $setupfile -replace "\\$"
                $setupfile = $setupfile -replace ":$"
            }
            
            if ($setupfile.Length -eq 1) {
                $setupfile = $setupfile + ':\SETUP.EXE'
                Write-Message -Level Verbose -Message 'Setup will start from ' + $setupfile
            } else {
                $setupfile = $setupfile + '\SETUP.EXE'
                Write-Message -Level Verbose -Message 'Setup will start from ' + $setupfile
            }
            
            # The removed code that guesses the volumes is too risky and can interrupt automation
            
            if (Test-Bound -ParameterName ConfigurationFile -Not) {
                # Copy the source config file to a temp destination. This way the original source file will be reusable.
                # After the temp file has been written, it will be copied to the remote computer if necessary
                $tempdir = Get-DbatoolsConfigValue -FullName path.dbatoolstemp
                $configfile = "$tempdir\Configuration$version.ini"
                
                Copy-Item "$script:PSModuleRoot\bin\installtemplate\$version\Configuration$version.ini" -Destination $configfile
                
                # Get the content of the copied ini file to use.
                $configcontent = Get-Content $configfile
                
                # replace default instance if instance is set
                if ($instance.InstanceName -ne 'MSSQLSERVER') {
                    (Get-Content -Path $configcontent).Replace("MSSQLSERVER", $instance.InstanceName) | Out-File $configcontent
                }
                
                #Check the number of cores available on the server. Summed because every processor can contain multiple cores
                $corecount = Get-DbaCmObject -ComputerName $instance.ComputerName -Credential $Credential -ClassName Win32_processor | Measure-Object NumberOfCores -Sum | Select-Object -ExpandProperty sum
                
                $instancecversion = $server.VersionMajor.ToString()
                if ($server.VersionMinor -eq "50") {
                    $instancecversion = "$($instanceversion)_50"
                }
                
                # TODO: implement the changes for tempdb
                if ($corecount -gt 8) {
                    $corecount = 8
                }
                
                # only change the values if they are specified
                if (Test-Bound -ParameterName DataPath) {
                    (Get-Content -Path $configcontent).Replace("SQLUSERDBDIR=""C:\Program Files\Microsoft SQL Server\MSSQL$instancecversion.MSSQLSERVER\MSSQL\Data""", $DataPath) | Out-File $configcontent
                }
                
                if (Test-Bound -ParameterName LogPath) {
                    (Get-Content -Path $configcontent).Replace("SQLUSERDBDIR=""C:\Program Files\Microsoft SQL Server\MSSQL$instancecversion.MSSQLSERVER\MSSQL\Data""", $LogPath) | Out-File $configcontent
                }
                
                if (Test-Bound -ParameterName TempPath) {
                    (Get-Content -Path $configcontent).Replace("SQLTEMPDBDIR=""C:\Program Files\Microsoft SQL Server\MSSQL$instancecversion.MSSQLSERVER\MSSQL\Data""", $LogPath) | Out-File $configcontent
                }
                
                if (Test-Bound -ParameterName BackupPath) {
                    (Get-Content -Path $configcontent).Replace('SQLBACKUPDIR="C:\Program Files\Microsoft SQL Server\MSSQL14.MSSQLSERVER\MSSQL\Backup"', 'SQLBACKUPDIR="' + $BackupPath + ':\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Backup"') | Out-File $configcontent
                }
                
                # TODO: Add support for ServiceAccount
                (Get-Content -Path $configcontent).Replace('SQLSYSADMINACCOUNTS="BUILTIN\Administrator"', 'SQLSYSADMINACCOUNTS="' + $AdminAccount) | Out-File $configcontent
                
                if ($SaveConfiguration) {
                    try {
                        $null = Copy-Item $configcontent -Destination $SaveConfiguration -ErrorAction Stop
                    } catch {
                        Stop-Function -Message "Could not copy file" -ErrorRecord $_ -Continue
                    }
                }
            }
            
            # enable remote installations
            if (-not $instance.IsLocalHost) {
                try {
                    # copy the file to the remote machine using PSSESSION
                    if ($Credential) {
                        $session = New-PSSession -ComputerName $instance.ComputerName -Credential $Credential -ErrorAction Stop
                    } else {
                        $session = New-PSSession -ComputerName $instance.ComputerName -ErrorAction Stop
                    }
                    
                    $tempdir = Invoke-Command -Session $session -ScriptBlock {
                        [System.IO.Path]::GetTempPath()
                    }
                    
                    $tempconfigini = "$tempdir\$($ConfigurationFile.Name)"
                    $null = Copy-Item -ToSession $session -Path $ConfigurationFile -Destination $tempconfigini -Force -ErrorAction Stop
                    $ConfigurationFile = $tempconfigini
                } catch {
                    Stop-Function -Message "Failure" -ErrorRecord $_ -Continue
                }
            }
            
            $scriptblock = {
                $setupfile = $args[0]
                $ConfigurationFile = $args[1]
                $SqlCredential = $args[2]
                $AuthenticationMode = $args[3]
                
                # should maybe test for the existence of setupfile here
                if ($AuthenticationMode -eq "Mixed") {
                    & $setupfile /ConfigurationFile=$ConfigurationFile /Q /IACCEPTSQLSERVERLICENSETERMS /SAPWD= $SqlCredential.GetNetworkCredential().Password
                } else {
                    & $setupfile /ConfigurationFile=$ConfigurationFile /Q /IACCEPTSQLSERVERLICENSETERMS
                }
            }
            
            Invoke-Command2 -ComputerName $instance.ComputerName -Credential $Credential -ArgumentList $setupfile, $ConfigurationFile, $SqlCredential, $AuthenticationMode -ScriptBlock
            
            # Now configure the right amount of TempDB files, actually no, let's mod the file
            # Set-DbaTempdbConfig -SqlInstance $server
        }
    }
}