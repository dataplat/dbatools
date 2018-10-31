function Install-DbaInstance {
    <#
    .SYNOPSIS

    This function will help you to quickly install a SQL Server instance. 

    .DESCRIPTION

    This function will help you to quickly install a SQL Server instance. 

    The number of TempDB files will be set to the number of cores with a maximum of eight.
    
    The perform volume maintenance right can be granted to the SQL Server account. If you happen to activate this in an environment where you are not allowed to do this,
    please revert that operation by removing the right from the local security policy (secpol.msc).

    You will see a screen with the users available on your machine. There you can choose the user that will act as Service Account for your SQL Server Install. This
    implies that the user has been created beforehand. 

    Note that the dowloaded installation file must be unzipped or an ISO has to be mounted. This will not be executed from this script. This function offers the possibility
    to execute an autosearch for the installation files. But you can just browse to the correct file if you like.

    .PARAMETER Version will hold the SQL Server version you wish to install. The variable will support autocomplete

    .PARAMETER Edition wull hold the different basic editions of SQL Server: Express, Standard, Enterprise and Developer. The variable will support autocomplete

    .PARAMETER StatsAndMl will hold the R and Python choices. The variable will support autocomplete. There will be a check on version; this parameter will revert to NULL if the version is below 2016
    
    .PARAMETER Appvolume will hold the volume letter of the application disc. If left empty, it will default to C, unless there is a drive named like App

    .PARAMETER DataVolume will hold the volume letter of the Data disc. If left empty, it will default to C, unless there is a drive named like Data

    .PARAMETER LogVolume will hold the volume letter of the Log disc. If left empty, it will default to C, unless there is a drive named like Log

    .PARAMETER TempVolume will hold the volume letter of the Temp disc. If left empty, it will default to C, unless there is a drive named like Temp

    .PARAMETER BackupVolume will hold the volume letter of the Backup disc. If left empty, it will default to C, unless there is a drive named like Backup

    .PARAMETER PerformVolumeMaintenance will set the policy for grant or deny this right to the SQL Server service account.

    .PARAMETER SaveFile will prompt you for a file location to save the new config file. Otherwise it will only be saved in the PowerShell bin directory.

    .PARAMETER Authentication will prompt you if you want mixed mode authentication or just Windows AD authentication. With Mixed Mode, you will be prompted for the SA password.

    .Inputs
    None

    .Outputs
    None

    .Example
    C:\PS> Install-DbaInstance

    This will run the installation with the default settings

    .Example

    C:\PS> Install-DbaInstance -AppVolume "G"

    This will run the installation with default setting apart from the application volume, this will be redirected to the G drive.

    .Example 

    C:\PS> Install-DbaInstance -Version 2016 -AppVolume "D" -DataVolume "E" -LogVolume "L" -PerformVolumeMaintenance "Yes" -SqlServerAccount "MyDomain\SvcSqlServer"

    This will install SQL Server 2016 on the D drive, the data on E, the logs on L and the other files on the autodetected drives. The perform volume maintenance
    right is granted and the domain account SvcSqlServer will be used as the service account for SqlServer.


    #>
    Param  (
        [ValidateSet("2008", "2008R2", "2012", "2014", "2016", "2017", "2019")][string]$Version, 
        [ValidateSet("Express", "Standard", "Enterprise", "Developer")][string]$Edition,
        [ValidateSet("Python", "R", "Python and R")][string]$StatsAndMl,
        [string]$AppVolume, 
        [string]$DataVolume, 
        [string]$LogVolume, 
        [string]$TempVolume, 
        [string]$BackupVolume,
        [string]$InstallFolder,
        [ValidateSet("Yes", "No")][string]$PerformVolumeMaintenance,
        [ValidateSet("Yes")][string]$SaveFile,
        [ValidateSet("Windows", "Mixed Mode")][string]$Authentication
    )

    # Check if the edition of SQL Server supports Python and R. Introduced in SQL 2016, it should not be allowed in earlier installations.

    IF ( $null -eq $StatsAndMl -or $StatsAndMl -ne '' ) {
        $Array = "2016", "2017", "2019"

        IF ($Version -notin $Array ) {
            $StatsAndMl = '';
        }
    }
    # Copy the source config file to a new destination. This way the original source file will be reusable.

    Copy-Item "$script:PSModuleRoot\bin\installtemplate\$version\$Edition\Configuration$version.ini" -Destination "$script:PSModuleRoot\bin\installtemplate\"

    $configini = Get-Content "$script:PSModuleRoot\bin\installtemplate\Configuration$version.ini"

    # Let the user set the Service Account for SQL Server. This does imply that the user has been created.

    $SqlServerAccount = Get-CimInstance -ClassName Win32_UserAccount  | Out-GridView -title 'Please select the Service Account for your Sql Server instance.' -PassThru | Select-Object -ExpandProperty Name
    
    # Get the installation folder of SQL Server. If the user didn't choose a specific folder, the autosearch will commence. It will take some time!
    #To limit the number of results, the search exludes the Windows

    IF ($InstallFolder::IsNullOrEmpty()) {
        
        Write-Message -level Verbose -Message "No Setup directory found. Switching to autosearch"

        $SetupFile = Get-CimInstance -ClassName cim_datafile -Filter "Extension = 'EXE'" |
            Where-Object {($_.Name.ToUpper().Contains('SETUP') -and $_.Name -notlike '*users*' -and $_.Name -notlike '*Program*' -and $_.Name -notlike '*Windows*')} | 
            Select-Object -Property @{Label = "FileLocation"; Expression = {$_.Name}} |
            Out-GridView -Title 'Please select the correct folder with the SQL Server installation Media' -PassThru | 
            Select-Object -ExpandProperty FileLocation
                
        Write-Message -Level Verbose -Message 'Selected Setup: ' + $SetupFile
    }
    else {
        $SetupFile = $SetupFile -replace "\\$"
        $SetupFile = $SetupFile -replace ":$"
    }

    IF ($SetupFile.Length -eq 1) {
        $SetupFile = $SetupFile + ':\SQLEXPR_x64_ENU\SETUP.EXE'
        Write-Message -Level Verbose -Message 'Setup will start from ' + $SetupFile
    } 
    else {
        $SetupFile = $SetupFile + '\SQLEXPR_x64_ENU\SETUP.EXE'
        Write-Message -Level Verbose -Message 'Setup will start from ' + $SetupFile
    }

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
    $NumberOfCores = Get-CimInstance -ClassName Win32_processor | Measure-Object NumberOfCores -Sum | Select-Object -ExpandProperty sum

    IF ($NumberOfCores -gt 8)
    { $NumberOfCores = 8 }

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

    Switch ($AlterDir) {
        Y {Write-Message -Level Verbose -Message "Yes, drives agreed, continuing"; }
        N {
            Write-Message -Level Verbose -Message "Datadrive: " $DataVolume
            $NewDataVolume = Read-Host "Your datavolume: "
            If ([string]::IsNullOrEmpty($NewDataVolume)) {
                Write-Message -Level Verbose -Message "Datavolume remains on " $DataVolume
            }
            else {
                $NewDataVolume = $NewDataVolume -replace "\\$"
                $NewDataVolume = $NewDataVolume -replace ":$"
                $DataVolume = $NewDataVolume
                Write-Message -Level Verbose -Message "DataVolume moved to " $DataVolume
            }
            
            Write-Message -Level Verbose -Message "logvolume: " $LogVolume
            $NewLogVolume = Read-Host "Your logvolume: "
            If ([string]::IsNullOrEmpty($NewLogVolume)) {
                Write-Message -Level Verbose -Message "Logvolume remains on " $LogVolume
            }
            else {
                $NewLogVolume = $NewLogVolume -replace "\\$"
                $NewLogVolume = $NewLogVolume -replace ":$"
                $LogVolume = $NewLogVolume
                Write-Message -Level Verbose -Message "LogVolume moved to " $LogVolume
            }


            Write-Message -Level Verbose -Message "TempVolume: " $TempVolume
            $NewTempVolume = Read-Host "Your TempVolume: "
            If ([string]::IsNullOrEmpty($NewTempVolume)) {
                Write-Message -Level Verbose -Message "TempVolume remains on " $TempVolume
            }
            else {
                $NewTempVolume = $NewTempVolume -replace "\\$"
                $NewTempVolume = $NewTempVolume -replace ":$"
                $TempVolume = $NewTempVolume
                Write-Message -Level Verbose -Message "TempVolume moved to " $TempVolume
            }

            Write-Message -Level Verbose -Message "AppVolume: " $AppVolume
            $NewAppVolume = Read-Host "Your AppVolume: "
            If ([string]::IsNullOrEmpty($NewAppVolume)) {
                Write-Message -Level Verbose -Message "AppVolume remains on " $AppVolume
            }
            else {
                $NewAppVolume = $NewAppVolume -replace "\\$"
                $NewAppVolume = $NewAppVolume -replace ":$"
                $AppVolume = $NewAppVolume
                Write-Message -Level Verbose -Message "AppVolume moved to " $AppVolume
            }

            Write-Message -Level Verbose -Message "BackupVolume: " $BackupVolume
            $NewBackupVolume = Read-Host "Your BackupVolume: "
            If ([string]::IsNullOrEmpty($NewBackupVolume)) {
                Write-Message -Level Verbose -Message "BackupVolume remains on " $BackupVolume
            }
            else {
                $NewBackupVolume = $NewBackupVolume -replace "\\$"
                $NewBackupVolume = $NewBackupVolume -replace ":$"
                $BackupVolume = $NewBackupVolume
                Write-Message -Level Verbose -Message "BackupVolume moved to " $BackupVolume
            }
        }
        Default {Write-Message -Level Verbose -Message "Drives agreed, continuing"; }
    }


    # Out-File -FilePath C:\Temp\ConfigurationFile2.ini -InputObject $startScript

    (Get-Content -Path $configini).Replace('SQLBACKUPDIR="E:\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Backup"', 'SQLBACKUPDIR="' + $BackupVolume + ':\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Backup"') | Out-File $configini

    (Get-Content -Path $configini).Replace('SQLUSERDBDIR="E:\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Data"', 'SQLUSERDBDIR="' + $DataVolume + ':\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Data"') | Out-File $configini

    (Get-Content -Path$configini).Replace('SQLTEMPDBDIR="E:\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Data"', 'SQLTEMPDBDIR="' + $TempVolume + ':\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Data"') | Out-File $configini

    (Get-Content -Path $configini).Replace('SQLUSERDBLOGDIR="E:\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Log"', 'SQLUSERDBLOGDIR="' + $LogVolume + ':\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Log"') | Out-File $configini

    (Get-Content -Path $configini).Replace('SQLSYSADMINACCOUNTS="WIN-NAJQHOBU8QD\Administrator"', 'SQLSYSADMINACCOUNTS="' + $SqlServerAccount)| Out-File $configini

    If ($SaveFile -eq "Yes") {
        $SaveFileLocation = Read-Host "Please enter your preferred directory for saving a copy of the configuration file: "
        Copy-Item $configini -Destination $SaveFileLocation
    }

    IF ($Authentication -eq "Mixed Mode") {
        $SAPassW = [PsCredential](Get-Credential -UserName "SA"  -Message "Please Enter the SA Password.")

        & $SetupFile /ConfigurationFile=$configini /Q /IACCEPTSQLSERVERLICENSETERMS /SAPWD= $SAPassW.GetNetworkCredential().Password

    }
    else {
        & $SetupFile /ConfigurationFile=$configini /Q /IACCEPTSQLSERVERLICENSETERMS
    }

    

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