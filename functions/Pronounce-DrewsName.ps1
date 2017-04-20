function Resolve-DrewsName {
  <#
    .SYNOPSIS
    Resolve Drew Furgiuele's name

    .DESCRIPTION
    I don't know how to pronounce his name. You don't know how to pronounce his name. It's awkward. Use PowerShell to avoid that awkwardness.

	.NOTES
	Original Author: Eugene Meidinger (@sqlgene)
	Tags: Pronounciation
	
	Website: https://dbatools.io
	Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
	License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.LINK
	https://dbatools.io/Resolve-DrewsName

    .EXAMPLE
    Resolve-DrewsName
    
    Just run it.
    #>

Add-Type -AssemblyName System.speech
$speak = New-Object System.Speech.Synthesis.SpeechSynthesizer
$speak.Speak('Drew Furjuel')

}