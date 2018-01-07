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

        .PARAMETER AvailabilityGroups
        Specify which Availability Groups to export (Dynamic Param)

        .PARAMETER NoClobber
        Do not overwrite existing export files.

        .PARAMETER SqlCredential
        Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

        $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

        SQL Server does not accept Windows credentials being passed as credentials. To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER WhatIf
        Shows you what it'd output if you were to run the command

        .PARAMETER Confirm
        Confirms each step/line of output

        .NOTES
        Tags: DisasterRecovery, AG, AvailabilityGroup
        Author: Chris Sommer (@cjsommer), cjsommer.com

        dbatools PowerShell module (https://dbatools.io)
        Copyright (C) 2016 Chrissy LeMaire
        License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

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
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("OutputLocation", "Path")]
        [string]$FilePath = "$([Environment]::GetFolderPath("MyDocuments"))\SqlAgExport",
        [switch]$NoClobber
    )

    begin {

        Write-Output "Beginning Export-DbaAvailabilityGroup on $SqlInstance"
        Write-Verbose "Connecting to SqlServer $SqlInstance"

        try {
            $server = Connect-SqlInstance -SqlInstance $SqlInstance -SqlCredential $SqlCredential
        }
        catch {
            Write-Warning "Can't connect to $SqlInstance. Moving on."
            Continue
        }
    }
    process {

        # Get all of the Availability Groups and filter if required
        $allags = $server.AvailabilityGroups

        if ($AvailabilityGroups) {
            Write-Verbose 'Filtering AvailabilityGroups'
            $allags = $allags | Where-Object { $_.name -in $AvailabilityGroups }
        }

        if ($allags.count -gt 0) {

            # Set and create the OutputLocation if it doesn't exist
            $sqlinst = $SqlInstance.Replace('\', '$')
            $OutputLocation = "$FilePath\$sqlinst"

            if (!(Test-Path $OutputLocation -PathType Container)) {
                New-Item -Path $OutputLocation -ItemType Directory -Force | Out-Null
            }

            # Script each Availability Group
            foreach ($ag in $allags) {
                $agname = $ag.Name

                # Set the outfile name
                if ($AppendDateToOutputFilename.IsPresent) {
                    $formatteddate = (Get-Date -Format 'yyyyMMdd_hhmm')
                    $outfile = "$OutputLocation\${AGname}_${formatteddate}.sql"
                }
                else {
                    $outfile = "$OutputLocation\$agname.sql"
                }

                # Check NoClobber and script out the AG
                if ($NoClobber.IsPresent -and (Test-Path -Path $outfile -PathType Leaf)) {
                    Write-Warning "OutputFile $outfile already exists. Skipping due to -NoClobber parameter"
                }
                else {
                    Write-output "Scripting Availability Group [$agname] on $SqlInstance to $outfile"

                    # Create comment block header for AG script
                    "/*" | Out-File -FilePath $outfile -Encoding ASCII -Force
                    " * Created by dbatools 'Export-DbaAvailabilityGroup' cmdlet on '$(Get-Date)'" | Out-File -FilePath $outfile -Encoding ASCII -Append
                    " * See https://dbatools.io/Export-DbaAvailabilityGroup for more help" | Out-File -FilePath $outfile -Encoding ASCII -Append

                    # Output AG and listener names
                    " *" | Out-File -FilePath $outfile -Encoding ASCII -Append
                    " * Availability Group Name: $($ag.name)" | Out-File -FilePath $outfile -Encoding ASCII -Append
                    $ag.AvailabilityGroupListeners | ForEach-Object { " * Listener Name: $($_.name)" } | Out-File -FilePath $outfile -Encoding ASCII -Append

                    # Output all replicas
                    " *" | Out-File -FilePath $outfile -Encoding ASCII -Append
                    $ag.AvailabilityReplicas | ForEach-Object { " * Replica: $($_.name)" } | Out-File -FilePath $outfile -Encoding ASCII -Append

                    # Output all databases
                    " *" | Out-File -FilePath $outfile -Encoding ASCII -Append
                    $ag.AvailabilityDatabases | ForEach-Object { " * Database: $($_.name)" } | Out-File -FilePath $outfile -Encoding ASCII -Append

                    # $ag | Select-Object -Property * | Out-File -FilePath $outfile -Encoding ASCII -Append

                    "*/" | Out-File -FilePath $outfile -Encoding ASCII -Append

                    # Script the AG
                    $ag.Script() | Out-File -FilePath $outfile -Encoding ASCII -Append
                }
            }
        }
        else {
            Write-Output "No Availability Groups detected on $SqlInstance"
        }
    }
    end {
    }
}
