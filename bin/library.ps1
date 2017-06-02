
#region Test whether the module had already been imported
if (([System.Management.Automation.PSTypeName]'SqlCollective.Dbatools.Configuration.Config').Type)
{
    # No need to load the library again, if the module was once already imported.
    $ImportLibrary = $false
}
else
{
    $ImportLibrary = $true
}
#endregion Test whether the module had already been imported

if ($ImportLibrary)
{
    $source = Get-Content (Join-Path $PSScriptRoot 'library.cs') -Raw

    #region Add Code
    try
    {
        $paramAddType = @{
            TypeDefinition = $source
            ErrorAction = 'Stop'
            ReferencedAssemblies = ([appdomain]::CurrentDomain.GetAssemblies() | Where-Object FullName -match "^Microsoft\.Management\.Infrastructure, |^System\.Numerics, " | Where-Object Location).Location
        }
        
        Add-Type @paramAddType
        
        #region PowerShell TypeData
        Update-TypeData -TypeName "SqlCollective.Dbatools.dbaSystem.DbatoolsException" -SerializationDepth 2 -ErrorAction Ignore
        Update-TypeData -TypeName "SqlCollective.Dbatools.dbaSystem.DbatoolsExceptionRecord" -SerializationDepth 2 -ErrorAction Ignore
        #endregion PowerShell TypeData
    }
    catch
    {
        #region Warning
        Write-Warning @'
Dear User,

in the name of the dbatools team I apologize for the inconvenience.
Generally, when something goes wrong we try to handle and interpret in an
understandable manner. Unfortunately, something went awry with importing
our main library, so all the systems making this possible would not be initialized
yet. We have taken great pains to avoid this issue but this notification indicates
we have failed.

Please, in order to help us prevent this from happening again, visit us at:
https://github.com/sqlcollaborative/dbatools/issues
and tell us about this failure. All information will be appreciated, but 
especially valuable are:
- Exports of the exception: $Error | Export-Clixml error.xml -Depth 4
- Screenshots
- Environment information (Operating System, Hardware Stats, .NET Version,
  PowerShell Version and whatever else you may consider of potential impact.)

Again, I apologize for the inconvenience and hope we will be able to speedily
resolve the issue.

Best Regards,
Friedrich Weinmann
aka "The guy who made most of The Library that Failed to import"

'@
        throw
        #endregion Warning
    }
    #endregion Add Code
}

#region Version Warning
$LibraryVersion = New-Object System.Version(1, 0, 1, 11)
if ($LibraryVersion -ne ([Sqlcollective.Dbatools.Utility.UtilityHost]::LibraryVersion))
{
    Write-Warning @"
A version missmatch between the dbatools library loaded and the one expected by
this module. This usually happens when you update the dbatools module and use
Remove-Module / Import-Module in order to load the latest version without
starting a new PowerShell instance.

Please restart the console to apply the library update, or unexpected behavior will likely occur.
"@
}
#endregion Version Warning