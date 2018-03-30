#ValidationTags#Messaging#
function Export-DbaAvailabilityGroup {
    <#
        .SYNOPSIS
            Exports SQL Server Availability Groups to a T-SQL file.

        .DESCRIPTION
            Exports SQL Server Availability Groups creation scripts to a T-SQL file. This is a function that is not available in SSMS.

        .PARAMETER SqlInstance
            The SQL Server instance name. SQL Server 2012 and above supported.

        .PARAMETER FilePath
            The directory name where the output files will be written. A sub directory with the format 'ServerName$InstanceName' will be created. A T-SQL scripts named 'AGName.sql' will be created under this subdirectory for each scripted Availability Group.

        .PARAMETER AvailabilityGroup
            The Availability Group(s) to export - this list is auto-populated from the server. If unspecified, all logins will be processed.

        .PARAMETER ExcludeAvailabilityGroup
            The Availability Group(s) to exclude - this list is auto-populated from the server.

        .PARAMETER NoClobber
            Do not overwrite existing export files.

        .PARAMETER SqlCredential
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

        .PARAMETER WhatIf
            Shows you what it'd output if you were to run the command

        .PARAMETER Confirm
            Confirms each step/line of output

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: DisasterRecovery, AG, AvailabilityGroup
            Author: Chris Sommer (@cjsommer), cjsommer.com

            dbatools PowerShell module (https://dbatools.io)
            Copyright (C) 2016 Chrissy LeMaire
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Export-DbaAvailabilityGroup

        .EXAMPLE
            Export-DbaAvailabilityGroup -SqlInstance sql2012

            Exports all Availability Groups from SQL server "sql2012". Output scripts are written to the Documents\SqlAgExports directory by default.

        .EXAMPLE
            Export-DbaAvailabilityGroup -SqlInstance sql2012 -FilePath C:\temp\availability_group_exports

            Exports all Availability Groups from SQL server "sql2012". Output scripts are written to the C:\temp\availability_group_exports directory.

        .EXAMPLE
            Export-DbaAvailabilityGroup -SqlInstance sql2012 -FilePath 'C:\dir with spaces\availability_group_exports' -AvailabilityGroups AG1,AG2

            Exports Availability Groups AG1 and AG2 from SQL server "sql2012". Output scripts are written to the C:\dir with spaces\availability_group_exports directory.

        .EXAMPLE
            Export-DbaAvailabilityGroup -SqlInstance sql2014 -FilePath C:\temp\availability_group_exports -NoClobber

            Exports all Availability Groups from SQL server "sql2014". Output scripts are written to the C:\temp\availability_group_exports directory. If the export file already exists it will not be overwritten.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$AvailabilityGroup,
        [object[]]$ExcludeAvailabilityGroup,
        [Alias("OutputLocation", "Path")]
        [string]$FilePath = "$([Environment]::GetFolderPath("MyDocuments"))\SqlAgExport",
        [switch]$NoClobber,
        [Alias('Silent')]
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.IsHadrEnabled -eq $false) {
                Stop-Function -Message "Hadr is not enabled on this instance" -Continue
            }
            else {
                # Get all of the Availability Groups and filter if required
                $ags = $server.AvailabilityGroups
            }

            if (Test-Bound 'AvailabilityGroup') {
                $ags = $ags | Where-Object Name -In $AvailabilityGroup
            }
            if (Test-Bound 'ExcludeAvailabilityGroup') {
                $ags = $ags | Where-Object Name -NotIn $ExcludeAvailabilityGroup
            }

            if ($ags) {

                # Set and create the OutputLocation if it doesn't exist
                $sqlinst = $instance.ToString().Replace('\', '$')
                $outputLocation = "$FilePath\$sqlinst"

                if (!(Test-Path $outputLocation -PathType Container)) {
                    $null = New-Item -Path $outputLocation -ItemType Directory -Force
                }

                # Script each Availability Group
                foreach ($ag in $ags) {
                    $agName = $ag.Name

                    # Set the outfile name
                    if ($AppendDateToOutputFilename.IsPresent) {
                        $formatteddate = (Get-Date -Format 'yyyyMMdd_hhmm')
                        $outFile = "$outputLocation\${AGname}_${formatteddate}.sql"
                    }
                    else {
                        $outFile = "$outputLocation\$agName.sql"
                    }

                    # Check NoClobber and script out the AG
                    if ($NoClobber.IsPresent -and (Test-Path -Path $outFile -PathType Leaf)) {
                        Write-Message -Level Warning -Message "OutputFile $outFile already exists. Skipping due to -NoClobber parameter"
                    }
                    else {
                        Write-Message -Level Verbose -Message "Scripting Availability Group [$agName] on $instance to $outFile"

                        # Create comment block header for AG script
                        "/*" | Out-File -FilePath $outFile -Encoding ASCII -Force
                        " * Created by dbatools 'Export-DbaAvailabilityGroup' cmdlet on '$(Get-Date)'" | Out-File -FilePath $outFile -Encoding ASCII -Append
                        " * See https://dbatools.io/Export-DbaAvailabilityGroup for more help" | Out-File -FilePath $outFile -Encoding ASCII -Append

                        # Output AG and listener names
                        " *" | Out-File -FilePath $outFile -Encoding ASCII -Append
                        " * Availability Group Name: $($ag.name)" | Out-File -FilePath $outFile -Encoding ASCII -Append
                        $ag.AvailabilityGroupListeners | ForEach-Object { " * Listener Name: $($_.name)" } | Out-File -FilePath $outFile -Encoding ASCII -Append

                        # Output all replicas
                        " *" | Out-File -FilePath $outFile -Encoding ASCII -Append
                        $ag.AvailabilityReplicas | ForEach-Object { " * Replica: $($_.name)" } | Out-File -FilePath $outFile -Encoding ASCII -Append

                        # Output all databases
                        " *" | Out-File -FilePath $outFile -Encoding ASCII -Append
                        $ag.AvailabilityDatabases | ForEach-Object { " * Database: $($_.name)" } | Out-File -FilePath $outFile -Encoding ASCII -Append

                        # $ag | Select-Object -Property * | Out-File -FilePath $outFile -Encoding ASCII -Append

                        "*/" | Out-File -FilePath $outFile -Encoding ASCII -Append

                        # Script the AG
                        try {
                            $ag.Script() | Out-File -FilePath $outFile -Encoding ASCII -Append
                            Get-ChildItem $outFile
                        }
                        catch {
                            Stop-Function -ErrorRecord $_ -Message "Error scripting out the availability groups. This is likely due to a bug in SMO." -Continue
                        }
                    }
                }
            }
            else {
                Write-Message -Level Output -Message "No Availability Groups detected on $instance"
            }
        }
    }
}