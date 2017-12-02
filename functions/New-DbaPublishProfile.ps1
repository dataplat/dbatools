Function New-DbaPublishProfile {
     <#
        .SYNOPSIS
            Creates a new Publish Profile.

        .DESCRIPTION
            The New-PublishProfile CmdLet generates a standard publish profile xml file that can be used by the DacFx (this and everything else) to control the deployment of your dacpac
            This generates a standard template XML which is enough to dpeloy a dacpac but it is highly recommended that you add additional options to the publish profile. 
            If you use Visual Studio you can open a publish.xml file and use the ui to edit the file -
            To create a new file, right click on an SSDT project, choose "Publish" then "Load Profile" and load your profile or create a new one. 
            Once you have loaded it in Visual Studio, clicking advanced shows you the list of options available to you.
            For a full list of options that you can add to the profile, google "sqlpackage.exe command line switches" or (https://msdn.microsoft.com/en-us/library/hh550080(v=vs.103).aspx)

        .PARAMETER targetDatabaseName
            The database name you are targetting
        .PARAMETER targetConnectionString
            The connection string to the database you are upgrading.
        .PARAMETER PublishProfilePath
            The path you would like to save the profile xml file.

        .PARAMETER EnableException
			By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
			This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
			Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: TAGS_HERE 
            Author: Richie lee (@bzzzt_io)

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
        .LINK
            https://dbatools.io/Test-Noun

        .EXAMPLE
        $PPP = "C:\Users\Richie\Documents\dbaToolsScripts"
        $TDN = "WorldWideImporters"
        $TCS = "SERVER=(localdb)\MSSQLLocalDB;Integrated Security=True;Database=master"
        
        This example will return filepath
        $newProfilePath = New-DbaPublishProfile -PublishProfilePath $PPP -targetDatabaseName $TDN -targetConnectionString $TCS

        This example will return the xml
        $newProfileXml = New-DbaPublishProfile -targetDatabaseName $TDN -targetConnectionString $TCS


    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $targetDatabaseName,
        [Parameter(Mandatory = $true)]
        $targetConnectionString,
        [Parameter(Mandatory = $false)]
        $PublishProfilePath,
        [switch][Alias('Silent')]$EnableException
    )
        $profileTemplate = "<?xml version=""1.0"" ?>
    <Project ToolsVersion=""14.0"" xmlns=""http://schemas.microsoft.com/developer/msbuild/2003"">
      <PropertyGroup>
        <TargetDatabaseName>{0}</TargetDatabaseName>
        <TargetConnectionString>{1}</TargetConnectionString>
        <ProfileVersionNumber>1</ProfileVersionNumber>
      </PropertyGroup>
    </Project>" -f $targetDatabaseName, $targetConnectionString
        if ([string]::IsNullOrEmpty($PublishProfilePath)) {
            Return $profileTemplate
        }
        else {
            $PublishProfile = Join-Path $PublishProfilePath "$targetDatabaseName.publish.xml"
            $profileTemplate | Out-File $PublishProfile
            Return $PublishProfile
        }
    }