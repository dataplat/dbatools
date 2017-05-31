<#
.SYNOPSIS
This command gets specified SSIS Environment and all its variables

.DESCRIPTION
This command gets all variables from specified environment from SSIS Catalog. All sensitive valus are decrypted.

.PARAMETER SqlInstance
The SQL Server instance.

.PARAMETER Project
The SSIS project name

.PARAMETER Folder
The Folder name that contains the project

.EXAMPLE
Get-DbaSsisProjectConfiguration -SqlInstance localhost -Project SSISProject -Folder DWH_ETL

.NOTES
Author: Bartosz Ratajczyk ( @b_ratajczyk )

dbatools PowerShell module (https://dbatools.io)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.
#>
function Get-DbaSsisProjectConfiguration {

[CmdletBinding()]
	Param (
		[parameter(Mandatory, ValueFromPipeline)]
		[Alias('SqlServer', 'ServerInstance')]
		[DbaInstanceParameter[]]$SqlInstance,
		[string]$Project,
        [string]$Folder
	)

    begin {

        try
        {
            Write-Verbose "Connecting to $SqlInstance"
            $connection = Connect-SqlInstance -SqlInstance $SqlInstance
        }
        catch
        {
            Stop-Function -Message "Could not connect to $SqlInstance"
            return
        }
        

        if ($connection.versionMajor -lt 11)
		{
            Stop-Function -Message "SSISDB catalog is only available on Sql Server 2012 and above, exiting." 
            return
		}

        try
		{
            $ISNamespace = "Microsoft.SqlServer.Management.IntegrationServices"

			Write-Verbose "Connecting to $SqlInstance Integration Services."
			$SSIS = New-Object "$ISNamespace.IntegrationServices" $connection
		}
		catch
		{
            Stop-Function -Message "Could not connect to Integration Services on $Source" -Silent $true
            return
		}

        Write-Verbose "Fetching SSIS Catalog and its folders"
        $catalog = $SSIS.Catalogs | Where-Object { $_.Name -eq "SSISDB" }
        $srcFolder = $catalog.Folders | Where-Object {$_.Name -eq $Folder}

        if($srcFolder) {
            $srcProject = $srcFolder.Projects | Where-Object {$_.Name -eq $Project}
            
            if($srcProject)
            {
                # first iterate project parameters and connection managers
                foreach($parameter in $srcProject.Parameters)
                {
                    [PSCustomObject]@{
                        Id                      = $parameter.Id
                        Name                    = $parameter.Name
                        DataType                = $parameter.DataType
                        IsRequired              = $parameter.Required
                        IsSensitive             = $parameter.Sensitive
                        Description             = $parameter.Description
                        DesignDefaultvalue      = $parameter.DesignDefaultvalue
                        DefaultValue            = $parameter.DefaultValue
                        ValueType               = $parameter.Literal
                        IsValueSet              = $parameter.ValueSet
                        ReferencedVariableName  = $parameter.ReferencedVariableName
                    }
                } # endforeach

                # then iterate package parameters
                foreach($package in $srcProject.Packages)
                {
                    foreach($parameter in $package.Parameters)
                    {
                        [PSCustomObject]@{
                            Id                      = $parameter.Id
                            Name                    = $parameter.Name
                            DataType                = $parameter.DataType
                            IsRequired              = $parameter.Required
                            IsSensitive             = $parameter.Sensitive
                            Description             = $parameter.Description
                            DesignDefaultvalue      = $parameter.DesignDefaultvalue
                            DefaultValue            = $parameter.DefaultValue
                            ValueType               = $parameter.Literal
                            IsValueSet              = $parameter.ValueSet
                            ReferencedVariableName  = $parameter.ReferencedVariableName
                        }
                    } # end foreach
                } # end foreach

            } # end if($project)
        }
    }

    process {

    }

    end {

    }

}