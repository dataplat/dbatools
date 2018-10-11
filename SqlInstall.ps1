function Install-DbaInstance {
    <#
    .SYNOPSIS

    This function will help you to quickly install a SQL Server instance. 

    .DESCRIPTION

    This function will help you to quickly install a SQL Server instance. 

    The number of TempDB files will be set to the number of cores with a maximum of eight.
    
    The perform volume maintenance right can be granted to the SQL Server account. If you happen to activate this in an environment where you are not allowed to do this,
    please revert that operation by removing the right from the local security policy (secpol.msc).

    Note that the dowloaded installation file must be unzipped, an ISO has to be mounted. This will not be executed from this script.

    .PARAMETER Version will hold the SQL Server version you wish to install. 
    
    .PARAMETER Appvolume will hold the volume letter of the application disc. If left empty, it will default to C, unless there is a drive named like App

    .PARAMETER DataVolume will hold the volume letter of the Data disc. If left empty, it will default to C, unless there is a drive named like Data

    .PARAMETER LogVolume will hold the volume letter of the Log disc. If left empty, it will default to C, unless there is a drive named like Log

    .PARAMETER TempVolume will hold the volume letter of the Temp disc. If left empty, it will default to C, unless there is a drive named like Temp

    .PARAMETER BackupVolume will hold the volume letter of the Backup disc. If left empty, it will default to C, unless there is a drive named like Backup

    .PARAMETER PerformVolumeMaintenance will set the boolean for grant or deny this right to the SQL Server service account.

    .PARAMETER SqlServiceAccount will hold the name of the service account

    .Inputs
    None

    .Outputs
    None

    .Example
    C:\PS> Install-DbaInstance

    This will run the installation with the default settings

    C:\PS> Install-DbaInstance -AppVolume "G"

    This will run the installation with default setting apart from the application volume, this will be redirected to the G drive.


    #>
    Param  (
        [string]$AppVolume, 
        [string]$DataVolume, 
        [string]$LogVolume, 
        [string]$TempVolume, 
        [string]$BackupVolume,
        [switch]$PerformVolumeMaintenance,
        [string]$SqlServerAccount,
        [int]$Version
    )

    $startScript = @'

;SQL Server 2014 Configuration File
[OPTIONS]
; Specifies a Setup work flow, like INSTALL, UNINSTALL, or UPGRADE. This is a required parameter. 
ACTION="Install"
; Detailed help for command line argument ROLE has not been defined yet. 
ROLE="AllFeatures_WithDefaults"
; Use the /ENU parameter to install the English version of SQL Server on your localized Windows operating system. 
ENU="True"
; Parameter that controls the user interface behavior. Valid values are Normal for the full UI,AutoAdvance for a simplied UI, and EnableUIOnServerCore for bypassing Server Core setup GUI block. 
; UIMODE="Normal"
; Setup will not display any user interface. 
QUIET="False"
; Setup will display progress only, without any user interaction. 
QUIETSIMPLE="False"
; Specify whether SQL Server Setup should discover and include product updates. The valid values are True and False or 1 and 0. By default SQL Server Setup will include updates that are found. 
UpdateEnabled="True"
; Specify if errors can be reported to Microsoft to improve future SQL Server releases. Specify 1 or True to enable and 0 or False to disable this feature. 
ERRORREPORTING="False"
; If this parameter is provided, then this computer will use Microsoft Update to check for updates. 
USEMICROSOFTUPDATE="False"
; Specifies features to install, uninstall, or upgrade. The list of top-level features include SQL, AS, RS, IS, MDS, and Tools. The SQL feature will install the Database Engine, Replication, Full-Text, and Data Quality Services (DQS) server. The Tools feature will install Management Tools, Books online components, SQL Server Data Tools, and other shared components. 
FEATURES=SQLENGINE
; Specify the location where SQL Server Setup will obtain product updates. The valid values are "MU" to search Microsoft Update, a valid folder path, a relative path such as .\MyUpdates or a UNC share. By default SQL Server Setup will search Microsoft Update or a Windows Update service through the Window Server Update Services. 
UpdateSource="MU"
; Displays the command line parameters usage 
HELP="False"
; Specifies that the detailed Setup log should be piped to the console. 
INDICATEPROGRESS="False"
; Specifies that Setup should install into WOW64. This command line argument is not supported on an IA64 or a 32-bit system. 
X86="False"
; Specify the root installation directory for shared components.  This directory remains unchanged after shared components are already installed. 
INSTALLSHAREDDIR="C:\Program Files\Microsoft SQL Server"
; Specify the root installation directory for the WOW64 shared components.  This directory remains unchanged after WOW64 shared components are already installed. 
INSTALLSHAREDWOWDIR="C:\Program Files (x86)\Microsoft SQL Server"
; Specify a default or named instance. MSSQLSERVER is the default instance for non-Express editions and SQLExpress for Express editions. This parameter is required when installing the SQL Server Database Engine (SQL), Analysis Services (AS), or Reporting Services (RS). 
INSTANCENAME="AXIANSDB01"
; Specify that SQL Server feature usage data can be collected and sent to Microsoft. Specify 1 or True to enable and 0 or False to disable this feature. 
SQMREPORTING="False"
; Specify the Instance ID for the SQL Server features you have specified. SQL Server directory structure, registry structure, and service names will incorporate the instance ID of the SQL Server instance. 
INSTANCEID="AXIANSDB01"
; Specify the installation directory. 
INSTANCEDIR="C:\Program Files\Microsoft SQL Server"
; Agent account name 
AGTSVCACCOUNT="NT AUTHORITY\NETWORK SERVICE"
; Auto-start service after installation.  
AGTSVCSTARTUPTYPE="Disabled"
; CM brick TCP communication port 
COMMFABRICPORT="0"
; How matrix will use private networks 
COMMFABRICNETWORKLEVEL="0"
; How inter brick communication will be protected 
COMMFABRICENCRYPTION="0"
; TCP port used by the CM brick 
MATRIXCMBRICKCOMMPORT="0"
; Startup type for the SQL Server service. 
SQLSVCSTARTUPTYPE="Automatic"
; Level to enable FILESTREAM feature at (0, 1, 2 or 3). 
FILESTREAMLEVEL="0"
; Set to "1" to enable RANU for SQL Server Express. 
ENABLERANU="True"
; Specifies a Windows collation or an SQL collation to use for the Database Engine. 
SQLCOLLATION="SQL_Latin1_General_CP1_CI_AS"
; Account for SQL Server service: Domain\User or system account. 
SQLSVCACCOUNT="NT Service\MSSQL$AXIANSDB01"
; Windows account(s) to provision as SQL Server system administrators. 
SQLSYSADMINACCOUNTS="WIN-NAJQHOBU8QD\Administrator"
; The default is Windows Authentication. Use "SQL" for Mixed Mode Authentication. 
SECURITYMODE="SQL"
; Default directory for the Database Engine log files. 
SQLUSERDBLOGDIR="E:\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Log"
; Default directory for the Database Engine backup files. 
SQLBACKUPDIR="E:\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Backup"
; Default directory for the Database Engine user databases. 
SQLUSERDBDIR="E:\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Data"
; Directory for Database Engine TempDB files. 
SQLTEMPDBDIR="E:\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Data"
; Provision current user as a Database Engine system administrator for %SQL_PRODUCT_SHORT_NAME% Express. 
ADDCURRENTUSERASSQLADMIN="True"
; Specify 0 to disable or 1 to enable the TCP/IP protocol. 
TCPENABLED="0"
; Specify 0 to disable or 1 to enable the Named Pipes protocol. 
NPENABLED="0"
; Startup type for Browser Service. 
BROWSERSVCSTARTUPTYPE="Automatic"
'@

    # Check if there are designated drives for Data, Log, TempDB, Back-up and Application.
    If ($DataVolume -eq $null -or $DataVolume -eq '') {
        $DataVolume = Get-Volume | 
            Where-Object {$_.DriveType -EQ 'Fixed' -and $null -ne $_.DriveLetter -and $_.FileSystemLabel -like '*Data*'} | 
            Select-Object -ExpandProperty DriveLetter
    }
    if ($LogVolume -eq $null -or $LogVolume -eq '') {
        $LogVolume = Get-Volume | 
            Where-Object {$_.DriveType -EQ 'Fixed' -and $null -ne $_.DriveLetter -and $_.FileSystemLabel -like '*Log*'} |  
            Select-Object -ExpandProperty DriveLetter
    }
    if ($TempVolume -eq $null -or $TempVolume -eq '') {
        $TempVolume = Get-Volume | 
            Where-Object {$_.DriveType -EQ 'Fixed' -and $null -ne $_.DriveLetter -and $_.FileSystemLabel -like '*TempDB*'} |  
            Select-Object -ExpandProperty DriveLetter
    }
    if ($AppVolume -eq $null -or $AppVolume -eq '') {
        $AppVolume = Get-Volume | 
            Where-Object {$_.DriveType -EQ 'Fixed' -and $null -ne $_.DriveLetter -and $_.FileSystemLabel -like '*App*'} |  
            Select-Object -ExpandProperty DriveLetter
    }
    if ($BackupVolume -eq $null -or $BackupVolume -eq '') {
        $BackupVolume = Get-Volume | 
            Where-Object {$_.DriveType -EQ 'Fixed' -and $null -ne $_.DriveLetter -and $_.FileSystemLabel -like '*Backup*'} |  
            Select-Object -ExpandProperty DriveLetter
    }
    #Check the number of cores available on the server. Summed because every processor can contain multiple cores
    $NumberOfCores = Get-WmiObject -Class Win32_processor |  
        Measure-Object NumberOfLogicalProcessors -Sum | 
        Select-Object -ExpandProperty sum

    IF ($NumberOfCores -gt 8)
    { $NumberOfCores = 8 }

    #Get the amount of available memory. If it's more than 40 GB, give the server 10% of the memory, else reserve 4 GB.

    $ServerMemory = Get-WmiObject -Class win32_physicalmemory | 
        Measure-Object Capacity -sum | 
        Select-Object -ExpandProperty sum
    $ServerMemoryMB = ($ServerMemory / 1024) / 1024

    If ($ServerMemoryMB -gt 40960) {
        $ServerWinMemory = $ServerMemoryMB * 0.1
        $ServerMemoryMB = $ServerMemoryMB - $ServerWinMemory
    }
    else {
        $ServerMemoryMB = $ServerMemoryMB - 4096
    }

    IF ($null -eq $DataVolume -or $DataVolume -eq '') {
        $DataVolume = 'C'
    }

    IF ($null -eq $LogVolume -or $LogVolume -eq '') {
        $LogVolume = $DataVolume
    }

    IF ( $null -eq $TempVolume -or $TempVolume -eq '') {
        $TempVolume = $DataVolume
    }

    IF ( $null -eq $AppVolume -or $AppVolume -eq '') {
        $AppVolume = 'C'
    }

    IF ( $null -eq $BackupVolume -or $BackupVolume -eq '') {
        $BackupVolume = $DataVolume
    }


    Write-Message -Level Verbose -Message 'Your datadrive:' $DataVolume
    Write-Message -Level Verbose -Message 'Your logdrive:' $LogVolume
    Write-Message -Level Verbose -Message 'Your TempDB drive:' $TempVolume
    Write-Message -Level Verbose -Message 'Your applicationdrive:' $AppVolume
    Write-Message -Level Verbose -Message 'Your Backup Drive:' $BackupVolume
    Write-Message -Level Verbose -Message 'Number of cores for your Database:' $NumberOfCores

    Write-Message -Level Verbose -Message  'Do you agree on the drives?'
    $AlterDir = Read-Host " ( Y / N )"

    $CheckLastTwoChar = ":\"
    $CheckLastChar = "\"

    Switch ($AlterDir) {
        Y {Write-Message -Level Verbose -Message "Yes, drives agreed, continuing"; }
        N {
            Write-Message -Level Verbose -Message "Datadrive: " $DataVolume
            $NewDataVolume = Read-Host "Your datavolume: "
            If ($NewDataVolume.Substring($NewDataVolume.Length - 2 -eq $CheckLastTwoChar) -and $NewDataVolume.Length -gt 2) {
                $NewDataVolume = $NewDataVolume.Substring(0, $NewDataVolume.Length - 2)
                $DataVolume = $NewDataVolume
                Write-Message -Level Verbose -Message "DataVolume moved to " $DataVolume
            }
            elseif ($NewDataVolume.Substring($NewDataVolume.Length - 1 -eq $CheckLastChar) -and $NewDataVolume.Length -gt 1) {
                $NewDataVolume = $NewDataVolume.Substring(0, $NewDataVolume.Length - 1)
                $DataVolume = $NewDataVolume
                Write-Message -Level Verbose -Message "DataVolume moved to " $DataVolume
            }
            else {
                $DataVolume = $NewDataVolume
                Write-Message -Level Verbose -Message "DataVolume moved to " $DataVolume
            }
            If ([string]::IsNullOrEmpty($NewDataVolume)) {
                Write-Message -Level Verbose -Message "Datavolume remains on " $DataVolume
            }
            Write-Message -Level Verbose -Message "logvolume: " $LogVolume
            $NewLogVolume = Read-Host "Your logvolume: "
            If ($NewLogVolume.Substring($NewLogVolume.Length - 2 -eq $CheckLastTwoChar) -and $NewLogVolume.Length -gt 2) {
                $NewLogVolume = $NewLogVolume.Substring(0, $NewLogVolume.Length - 2)
                $LogVolume = $NewLogVolume
                Write-Message -Level Verbose -Message "LogVolume moved to " $LogVolume
            }
            elseif ($NewLogVolume.Substring($NewLogVolume.Length - 1 -eq $CheckLastChar) -and $NewLogVolume.Length -gt 1) {
                $NewLogVolume = $NewLogVolume.Substring(0, $NewLogVolume.Length - 1)
                $LogVolume = $NewLogVolume
                Write-Message -Level Verbose -Message "LogVolume moved to " $LogVolume
            }
            else {
                $LogVolume = $NewLogVolume
                Write-Message -Level Verbose -Message "LogVolume moved to " $LogVolume
            }
            If ([string]::IsNullOrEmpty($NewLogVolume)) {
                Write-Message -Level Verbose -Message "Logvolume remains on " $LogVolume
            }

            Write-Message -Level Verbose -Message "TempVolume: " $TempVolume
            $NewTempVolume = Read-Host "Your TempVolume: "
            If ($NewTempVolume.Substring($NewTempVolume.Length - 2 -eq $CheckLastTwoChar) -and $NewTempVolume.Length -gt 2) {
                $NewTempVolume = $NewTempVolume.Substring(0, $NewTempVolume.Length - 2)
                $TempVolume = $NewTempVolume
                Write-Message -Level Verbose -Message "TempVolume moved to " $TempVolume
            }
            elseif ($NewTempVolume.Substring($NewTempVolume.Length - 1 -eq $CheckLastChar) -and $NewTempVolume.Length -gt 1) {
                $NewTempVolume = $NewTempVolume.Substring(0, $NewTempVolume.Length - 1)
                $TempVolume = $NewTempVolume
                Write-Message -Level Verbose -Message "TempVolume moved to " $TempVolume
            }
            else {
                $TempVolume = $NewTempVolume
                Write-Message -Level Verbose -Message "TempVolume moved to " $TempVolume
            }
            If ([string]::IsNullOrEmpty($NewTempVolume)) {
                Write-Message -Level Verbose -Message "TempVolume remains on " $TempVolume
            }

            Write-Message -Level Verbose -Message "AppVolume: " $AppVolume
            $NewAppVolume = Read-Host "Your AppVolume: "
            If ($NewAppVolume.Substring($NewAppVolume.Length - 2 -eq $CheckLastTwoChar) -and $NewAppVolume.Length -gt 2) {
                $NewAppVolume = $NewAppVolume.Substring(0, $NewAppVolume.Length - 2)
                $AppVolume = $NewAppVolume
                Write-Message -Level Verbose -Message "AppVolume moved to " $AppVolume
            }
            elseif ($NewAppVolume.Substring($NewAppVolume.Length - 1 -eq $CheckLastChar) -and $NewAppVolume.Length -gt 1) {
                $NewAppVolume = $NewAppVolume.Substring(0, $NewAppVolume.Length - 1)
                $AppVolume = $NewAppVolume
                Write-Message -Level Verbose -Message "AppVolume moved to " $AppVolume
            }
            else {
                $AppVolume = $NewAppVolume
                Write-Message -Level Verbose -Message "AppVolume moved to " $AppVolume
            }
            If ([string]::IsNullOrEmpty($NewAppVolume)) {
                Write-Message -Level Verbose -Message "AppVolume remains on " $AppVolume
            }

            Write-Message -Level Verbose -Message "BackupVolume: " $BackupVolume
            $NewBackupVolume = Read-Host "Your BackupVolume: "
            If ($NewBackupVolume.Substring($NewBackupVolume.Length - 2 -eq $CheckLastTwoChar) -and $NewBackupVolume.Length -gt 2) {
                $NewBackupVolume = $NewBackupVolume.Substring(0, $NewBackupVolume.Length - 2)
                $BackupVolume = $NewBackupVolume
                Write-Message -Level Verbose -Message "BackupVolume moved to " $BackupVolume
            }
            elseif ($NewBackupVolume.Substring($NewBackupVolume.Length - 1 -eq $CheckLastChar) -and $NewBackupVolume.Length -gt -1) {
                $NewBackupVolume = $NewBackupVolume.Substring(0, $NewBackupVolume.Length - 1)
                $BackupVolume = $NewBackupVolume
                Write-Message -Level Verbose -Message "BackupVolume moved to " $BackupVolume
            }
            else {
                $BackupVolume = $NewBackupVolume
                Write-Message -Level Verbose -Message "BackupVolume moved to " $BackupVolume
            }
            If ([string]::IsNullOrEmpty($NewBackupVolume)) {
                Write-Message -Level Verbose -Message "BackupVolume remains on " $BackupVolume
            }
        }
        Default {Write-Message -Level Verbose -Message "Drives agreed, continuing"; }
    }

    $CheckLastTwoChar = ":\"
    $CheckLastChar = "\"

    $SetupFile = Read-Host -Prompt 'Please enter the root location for Setup.exe'
    IF ($SetupFile.Length -gt 1) {
        $C2 = $SetupFile.Substring($SetupFile.Length - 2)
        $C1 = $SetupFile.Substring($SetupFile.Length - 1)
        If ($C2 -eq $CheckLastTwoChar) {
            $debug = $SetupFile.Substring($SetupFile.Length - 2)
            Write-Message -Level Verbose -Message $debug '/' $CheckLastTwoChar
            $SetupFile = $SetupFile.Substring(0, $SetupFile.Length - 2)
            Write-Message -Level Verbose -Message $SetupFile
        }
        elseif ($C1 -eq $CheckLastChar) {
            $SetupFile = $SetupFile.Substring(0, $SetupFile.Length - 1)
            Write-Message -Level Verbose -Message $SetupFile
        }
    }
    IF ($SetupFile.Length -eq 1) {
        $SetupFile = $SetupFile + ':\SQLEXPR_x64_ENU\SETUP.EXE'
        Write-Message -Level Verbose -Message 'Setup will start from ' + $SetupFile
    } 
    else {
        $SetupFile = $SetupFile + '\SQLEXPR_x64_ENU\SETUP.EXE'
        Write-Message -Level Verbose -Message 'Setup will start from ' + $SetupFile
    }


    $ConfigFile = 'c:\temp\'

    if ( -Not (Test-Path -Path $ConfigFile ) ) {
        New-Item -ItemType directory -Path $ConfigFile
    }

    Out-File -FilePath C:\Temp\ConfigurationFile2.ini -InputObject $startScript

    $FileLocation2 = $ConfigFile + 'ConfigurationFile2.ini'

    (Get-Content -Path $FileLocation2).Replace('SQLBACKUPDIR="E:\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Backup"', 'SQLBACKUPDIR="' + $BackupVolume + ':\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Backup"') | Out-File $FileLocation2

    (Get-Content -Path $FileLocation2).Replace('SQLUSERDBDIR="E:\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Data"', 'SQLUSERDBDIR="' + $DataVolume + ':\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Data"') | Out-File $FileLocation2

    (Get-Content -Path $FileLocation2).Replace('SQLTEMPDBDIR="E:\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Data"', 'SQLTEMPDBDIR="' + $TempVolume + ':\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Data"') | Out-File $FileLocation2

    (Get-Content -Path $FileLocation2).Replace('SQLUSERDBLOGDIR="E:\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Log"', 'SQLUSERDBLOGDIR="' + $LogVolume + ':\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Log"') | Out-File $FileLocation2

    (Get-Content -Path $FileLocation2).Replace('SQLSYSADMINACCOUNTS="WIN-NAJQHOBU8QD\Administrator"', 'SQLSYSADMINACCOUNTS="' + $env:COMPUTERNAME + '\Administrator"')| Out-File $FileLocation2

    #$SetupFile = 'C:\Users\Administrator\Downloads\SQLEXPR_x64_ENU\Setup.exe'
    #$ConfigFile = 'C:\temp\ConfigurationFile2.ini'

    $SAPassW = '[InsertPasswordHere]'

    & $SetupFile /ConfigurationFile=$FileLocation2 /Q /IACCEPTSQLSERVERLICENSETERMS /SAPWD=$SAPassW

    # Grant service account the right to perform volume maintenance
    # code found at https://social.technet.microsoft.com/Forums/windows/en-US/5f293595-772e-4d0c-88af-f54e55814223/adding-domain-account-to-the-local-policy-user-rights-assignment-perform-volume-maintenance?forum=winserverpowershell

    if ($PerformVolumeMaintenance) {
        ## <--- Configure here
        $accountToAdd = 'NT Service\MSSQL$AXIANSDB01'
        ## ---> End of Config
        $sidstr = $null


        try {
            $ntprincipal = new-object System.Security.Principal.NTAccount "$accountToAdd"
            $sid = $ntprincipal.Translate([System.Security.Principal.SecurityIdentifier])
            $sidstr = $sid.Value.ToString()
        }
        catch {
            $sidstr = $null
        }
        Write-Message -Level Verbose -Message "Account: $($accountToAdd)" -ForegroundColor DarkCyan
        if ( [string]::IsNullOrEmpty($sidstr) ) {
            Write-Message -Level Verbose -Message "Account not found!" -ForegroundColor Red
            #exit -1
        }

        Write-Message -Level Verbose -Message "Account SID: $($sidstr)" -ForegroundColor DarkCyan
        $tmp = ""
        $tmp = [System.IO.Path]::GetTempFileName()
        Write-Message -Level Verbose -Message "Export current Local Security Policy" -ForegroundColor DarkCyan
        secedit.exe /export /cfg "$($tmp)" 
        $c = ""
        $c = Get-Content -Path $tmp
        $currentSetting = ""
        foreach ($s in $c) {
            if ( $s -like "SeManageVolumePrivilege*") {
                $x = $s.split("=", [System.StringSplitOptions]::RemoveEmptyEntries)
                $currentSetting = $x[1].Trim()
            }
        }


        if ( $currentSetting -notlike "*$($sidstr)*" ) {
            Write-Message -Level Verbose -Message "Modify Setting ""Perform Volume Maintenance Task""" -ForegroundColor DarkCyan
       
            if ( [string]::IsNullOrEmpty($currentSetting) ) {
                $currentSetting = "*$($sidstr)"
            }
            else {
                $currentSetting = "*$($sidstr),$($currentSetting)"
            }
       
            Write-Message -Level Verbose -Message "$currentSetting"
       
            $outfile = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Privilege Rights]
SeManageVolumePrivilege = $($currentSetting)
"@
       
            $tmp2 = ""
            $tmp2 = [System.IO.Path]::GetTempFileName()
       
       
            Write-Message -Level Verbose -Message "Import new settings to Local Security Policy" -ForegroundColor DarkCyan
            $outfile | Set-Content -Path $tmp2 -Encoding Unicode -Force
            #notepad.exe $tmp2
            Push-Location (Split-Path $tmp2)
       
            try {
                secedit.exe /configure /db "secedit.sdb" /cfg "$($tmp2)" /areas USER_RIGHTS 
                #Write-Message -Level Verbose -Message "secedit.exe /configure /db ""secedit.sdb"" /cfg ""$($tmp2)"" /areas USER_RIGHTS "
            }
            finally {  
                Pop-Location
            }
        }
        else {
            Write-Message -Level Verbose -Message "NO ACTIONS REQUIRED! Account already in ""Perform Volume Maintenance Task""" -ForegroundColor DarkCyan
        }
        Write-Message -Level Verbose -Message "Done." -ForegroundColor DarkCyan 
    }



    # Now for the fun part, alter the database settings
    # First we need to install (if necessary) the SQL commandlets

    Install-PackageProvider -Name NuGet -Force

    Install-Module -name SqlServer -Force

    Import-Module SqlServer -Force

    #Go into the realms of SQL Server

    SQLSERVER:

    #most queries work best when you're around databases. 
    Set-Location .\SQL\$env:COMPUTERNAME\AXIANSDB01\databases

    #Let's setup the Max Dop, CTfP and max server memory.
    if ($null -eq $Ctp -or $Ctp -eq '') {
        $Ctp = 40
    }

    $sql1 = @'
      USE master;
      GO
      EXEC sp_configure 'show advanced options',1;
      go
      reconfigure with override;
      exec sp_configure 'max degree of parallelism', 
'@

    $sql2 = @'
      ;
      GO
      RECONFIGURE WITH OVERRIDE;
      EXEC sp_configure 'Cost threshold for parallelism', 
'@

    $sql3 = @'
    ;
    GO
    RECONFIGURE WITH OVERRIDE
    EXEC sp_configure 'max server memory'
'@

    $sql4 = @'
 ;
 GO
 RECONFIGURE WITH OVERRIDE
 EXEC sp_configure 'show advanced options', 0;
 GO
 RECONFIGURE WITH OVERRIDE
'@

    $totalQuery = $sql1 + $NumberOfCores + $sql2 + $Ctp + $sql3 + $ServerMemoryMB + $sql4

    Invoke-Sqlcmd -Database master -Query $totalQuery

    #Now configure the right amount of TempDB files.

    $val = 1

    WHILE ($val -ne $NumberOfCores) {
        $sqlM = 'ALTER DATABASE tempdb ADD FILE ( NAME = N''tempdev' + $val + ''', FILENAME = N''' + $TempVolume + ':\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\DATA\tempdev' + $val + '.ndf'' , SIZE = 64MB , FILEGROWTH = 64MB)'
        Invoke-Sqlcmd -Database master -Query $sqlM

        $val++
    }

    #And make sure the standard one has the same configuration as the new ones to make sure the parallelism works
    $sql = @'
ALTER DATABASE TempDB   
MODIFY FILE  
(NAME = tempdev,  
SIZE = 64MB, FILEGROWTH = 64MB);  
GO  
'@

    Invoke-Sqlcmd -Database TempDB -Query $sql

    #Turn off SA, primary break-in point of the naughty users

    $sql = 'ALTER LOGIN sa DISABLE'

    Invoke-Sqlcmd -Database master -Query $sql
}