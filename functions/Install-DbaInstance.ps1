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

    .PARAMETER Version 
            Version will hold the SQL Server version you wish to install. The variable will support autocomplete

    .PARAMETER Edition 
            Edition will hold the different basic editions of SQL Server: Express, Standard, Enterprise and Developer. The variable will support autocomplete

    .PARAMETER Role 
            Role Will hold the option to install all features with defaults. Version is still mandatory. if no Edition is selected, it will default to Express!

    .PARAMETER StatsAndMl 
            StatsandML will hold the R and Python choices. The variable will support autocomplete. There will be a check on version; this parameter will revert to NULL if the version is below 2016
    
    .PARAMETER Appvolume 
            AppVolume will hold the volume letter of the application disc. if left empty, it will default to C, unless there is a drive named like App

    .PARAMETER DataVolume 
            DataVolume will hold the volume letter of the Data disc. if left empty, it will default to C, unless there is a drive named like Data

    .PARAMETER LogVolume 
            LogVolume will hold the volume letter of the Log disc. if left empty, it will default to C, unless there is a drive named like Log

    .PARAMETER TempVolume 
            TempVolume will hold the volume letter of the Temp disc. if left empty, it will default to C, unless there is a drive named like Temp

    .PARAMETER BackupVolume 
            BackupVolume will hold the volume letter of the Backup disc. if left empty, it will default to C, unless there is a drive named like Backup

    .PARAMETER PerformVolumeMaintenance 
            PerformVolumeMaintenance will set the policy for grant or deny this right to the SQL Server service account.

    .PARAMETER SaveFile 
            SaveFile will prompt you for a file location to save the new config file. Otherwise it will only be saved in the PowerShell bin directory.

    .PARAMETER Authentication 
            Authentication will prompt you if you want mixed mode authentication or just Windows AD authentication. With Mixed Mode, you will be prompted for the SA password.

    .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .Example
    C:\PS> Install-DbaInstance -role "AllFeaturesWithDefaults"

    This will run the installation with the default settings

    .Example

    C:\PS> Install-DbaInstance -AppVolume "G"

    This will run the installation with default setting apart from the application volume, this will be redirected to the G drive.

    .Example 

    C:\PS> Install-DbaInstance -Version 2016 -AppVolume "D" -DataVolume "E" -LogVolume "L" -PerformVolumeMaintenance -SqlServerAccount "MyDomain\SvcSqlServer"

    This will install SQL Server 2016 on the D drive, the data on E, the logs on L and the other files on the autodetected drives. The perform volume maintenance
    right is granted and the domain account SvcSqlServer will be used as the service account for SqlServer.


    #>
    Param  (
        [parameter(Mandatory)]
        [ValidateSet("2008", "2008R2", "2012", "2014", "2016", "2017", "2019")]
        [string]$Version, 
        [ValidateSet("Express", "Standard", "Enterprise", "Developer")]
        [string]$Edition = "Express",
        [ValidateSet("AllFeaturesWithDefaults", "Custom")]
        [string]$Role,
        [ValidateSet("Python", "R", "Python and R")]
        [string]$StatsAndMl,
        [string]$AppVolume, 
        [string]$DataVolume, 
        [string]$LogVolume, 
        [string]$TempVolume, 
        [string]$BackupVolume,
        [string]$InstallFolder,
        [switch]$PerformVolumeMaintenance,
        [switch]$SaveFile,
        [ValidateSet("Windows", "Mixed Mode")]
        [string]$Authentication,
        [switch]$EnableException
    )


    if (-not $version) {
        Stop-Function -Message "You need to specify a SQL Server Version to run this function." -Continue -EnableException $EnableException
        #Reminder to check on all faulty combinations that might be possible
    }

    if($null -eq $Role -or $Role -eq "AllFeaturesWithDefaults"){
        #Reminder to check which paramters should be set to run a default.
    }

    # Check if the edition of SQL Server supports Python and R. Introduced in SQL 2016, it should not be allowed in earlier installations.

    if ( $null -eq $StatsAndMl -or $StatsAndMl -ne '' ) {
        $Array = "2016", "2017", "2019"

        if ($Version -notin $Array ) {
            $StatsAndMl = '';
        }
    }
    # Copy the source config file to a new destination. This way the original source file will be reusable.

    Copy-Item "$script:PSModuleRoot\bin\installtemplate\$version\$Edition\Configuration$version.ini" -Destination "$script:PSModuleRoot\bin\installtemplate\"

    $configini = Get-Content "$script:PSModuleRoot\bin\installtemplate\Configuration$version.ini"

    # Let the user set the Service Account for SQL Server. This does imply that the user has been created.

    $SqlServerAccount = Get-CimInstance -ClassName Win32_UserAccount  | Out-GridView -title 'Please select the Service Account for your Sql Server instance.' -PassThru | Select-Object -ExpandProperty Name

    if ($Authentication -eq "Mixed Mode") {
        $SAPassW = [PsCredential](Get-Credential -UserName "SA"  -Message "Please Enter the SA Password.")
    }
    
    # Get the installation folder of SQL Server. if the user didn't choose a specific folder, the autosearch will commence. It will take some time!
    #To limit the number of results, the search exludes the Windows

    if ($InstallFolder::IsNullOrEmpty()) {
        
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

    if ($SetupFile.Length -eq 1) {
        $SetupFile = $SetupFile + ':\SQLEXPR_x64_ENU\SETUP.EXE'
        Write-Message -Level Verbose -Message 'Setup will start from ' + $SetupFile
    } 
    else {
        $SetupFile = $SetupFile + '\SQLEXPR_x64_ENU\SETUP.EXE'
        Write-Message -Level Verbose -Message 'Setup will start from ' + $SetupFile
    }

    # Check if there are designated drives for Data, Log, TempDB, Back-up and Application.
    if ($DataVolume -eq $null -or $DataVolume -eq '') {
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

    if ($NumberOfCores -gt 8)
    { $NumberOfCores = 8 }

    if ($null -eq $DataVolume -or $DataVolume -eq '') {
        $DataVolume = 'C'
    }

    if ($null -eq $LogVolume -or $LogVolume -eq '') {
        $LogVolume = $DataVolume
    }

    if ( $null -eq $TempVolume -or $TempVolume -eq '') {
        $TempVolume = $DataVolume
    }

    if ( $null -eq $AppVolume -or $AppVolume -eq '') {
        $AppVolume = 'C'
    }

    if ( $null -eq $BackupVolume -or $BackupVolume -eq '') {
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

    switch ($AlterDir) {
        Y {Write-Message -Level Verbose -Message "Yes, drives agreed, continuing"; }
        N {
            Write-Message -Level Verbose -Message "Datadrive: " $DataVolume
            $NewDataVolume = Read-Host "Your datavolume: "
            if ([string]::IsNullOrEmpty($NewDataVolume)) {
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
            if ([string]::IsNullOrEmpty($NewLogVolume)) {
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
            if ([string]::IsNullOrEmpty($NewTempVolume)) {
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
            if ([string]::IsNullOrEmpty($NewAppVolume)) {
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
            if ([string]::IsNullOrEmpty($NewBackupVolume)) {
                Write-Message -Level Verbose -Message "BackupVolume remains on " $BackupVolume
            }
            else {
                $NewBackupVolume = $NewBackupVolume -replace "\\$"
                $NewBackupVolume = $NewBackupVolume -replace ":$"
                $BackupVolume = $NewBackupVolume
                Write-Message -Level Verbose -Message "BackupVolume moved to " $BackupVolume
            }
        }
        default {Write-Message -Level Verbose -Message "Drives agreed, continuing"; }
    }

    (Get-Content -Path $configini).Replace('SQLBACKUPDIR="E:\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Backup"', 'SQLBACKUPDIR="' + $BackupVolume + ':\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Backup"') | Out-File $configini

    (Get-Content -Path $configini).Replace('SQLUSERDBDIR="E:\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Data"', 'SQLUSERDBDIR="' + $DataVolume + ':\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Data"') | Out-File $configini

    (Get-Content -Path$configini).Replace('SQLTEMPDBDIR="E:\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Data"', 'SQLTEMPDBDIR="' + $TempVolume + ':\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Data"') | Out-File $configini

    (Get-Content -Path $configini).Replace('SQLUSERDBLOGDIR="E:\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Log"', 'SQLUSERDBLOGDIR="' + $LogVolume + ':\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\Log"') | Out-File $configini

    (Get-Content -Path $configini).Replace('SQLSYSADMINACCOUNTS="WIN-NAJQHOBU8QD\Administrator"', 'SQLSYSADMINACCOUNTS="' + $SqlServerAccount)| Out-File $configini

    if ($SaveFile -eq "Yes") {
        $SaveFileLocation = Read-Host "Please enter your preferred directory for saving a copy of the configuration file: "
        Copy-Item $configini -Destination $SaveFileLocation
    }

    if ($Authentication -eq "Mixed Mode") {
        & $SetupFile /ConfigurationFile=$configini /Q /IACCEPTSQLSERVERLICENSETERMS /SAPWD= $SAPassW.GetNetworkCredential().Password

    }
    else {
        & $SetupFile /ConfigurationFile=$configini /Q /IACCEPTSQLSERVERLICENSETERMS
    }

    

    

    #Now configure the right amount of TempDB files.

    $val = 1

    while ($val -ne $NumberOfCores) {
        $sqlM = 'ALTER DATABASE tempdb ADD FILE ( NAME = N''tempdev' + $val + ''', FILENAME = N''' + $TempVolume + ':\Program Files\Microsoft SQL Server\MSSQL12.AXIANSDB01\MSSQL\DATA\tempdev' + $val + '.ndf'' , SIZE = 64MB , FILEGROWTH = 64MB)'
        Invoke-Sqlcmd -Database master -Query $sqlM

        $val++
    }

    #And make sure the standard one has the same configuration as the new ones to make sure the parallelism works
    $sql = @'
ALTER DATABASE TempDB   
MODifY FILE  
(NAME = tempdev,  
SIZE = 64MB, FILEGROWTH = 64MB);  
GO  
'@

    Invoke-Sqlcmd -Database TempDB -Query $sql
}