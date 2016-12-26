Function Rename-LogicalFile
{
<# 
	.SYNOPSIS
	Internal function. Renames logical files.
    Can either use  prefix with -Prefix, ALL files log and data will be prefixed

    Or pass in a mapping hash like:
    $mapping = @{
        'File1'='NewNamefile1'
        'File3'='somethingelse'
    }
    Can select which files need remappping.
#>
	[CmdletBinding()]
	param (
        [parameter(Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance")]
		[object]$SqlServer,
		[string]$DbName,
		[System.Management.Automation.PSCredential]$SqlCredential,
        [string]$Prefix,
        [hashtable]$Mapping
	)
    $Functionname = "Rename-LogicalFile"
    if ('' -ne $prefix -and $mapping.count -ne 0)
    {
        Write-Error "$functionname only accepts a new prefix OR a mapping hash"
        return $false
    }

    $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $SqlCredential
    if ($null -eq $server.Databases[$DbName])
    {
        Write-Error "$functionname - Database $dbname does not exist"
        return $false
        break
    }
    $database = $server.Databases[$DbName]
    Write-Verbose "$functionname - Getting data files"
    $LogicalFiles = @()
    foreach ($filegroup in $database.filegroups)
    {
        foreach($file in $filegroup.files)
        {
            $LogicalFiles += $file
        }
    }
    Write-Verbose "$functionname - getting log files"
    foreach ($file in $database.LogFiles)
    {
        $LogicalFiles += $file
    }
    if ($null -ne $Mapping -and $LogicalFiles.count -lt $Mapping.count)
    {
        Write-Error "FunctionName - More mappings than files"
        return $false
    }
    Write-Verbose "Filecont = $($LogicalFiles.count)"
    if ('' -ne $prefix)
    {
        foreach ($file in $LogicalFiles)
        {
            $nname = $prefix+$file.name
            Write-Verbose "$Functionname prefixing $($file.name) to $nname"
            try {
                $file.reName($nname)    
            }
            catch  {
                Write-Exception $_
                return 
            }
            
        }
    }
    if ($null -ne $Mapping)
    {
        foreach ($file in $LogicalFiles)
        {
            if ($null -eq $Mapping[($file.name)])
            {
                Write-Verbose "$functionname - No mapping for $($file.name) "
            }
            else
            {
                $nname = $Mapping[($file.name)]
                Write-Verbose "$Functionname - mapping $($file.name) to $nname"
                try {
                    $file.reName($nname)    
                }
                catch  {
                    Write-Exception $_
                    return 
                }
            }
        }
    }
    return $true
}