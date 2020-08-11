function Write-HostColor {
    <#
    .SYNOPSIS
        Function that recognizes html-style tags to insert color into printed text.

    .DESCRIPTION
        Function that recognizes html-style tags to insert color into printed text.

        Color tags should be designed to look like this:
        <c="<console color>">Text</c>
        For example this would be a valid string:
        "This message should <c="red">partially be painted in red</c>."

        This allows specifying color within strings and avoids having to piece together colored text in multiple calls to Write-Host.
        Only colors that are part of the ConsoleColor enumeration can be used. Bad colors will be ignored in favor of the default color.

    .PARAMETER String
        The message to write to host.

    .PARAMETER DefaultColor
        Default: (Get-DbatoolsConfigValue -Name "message.infocolor")
        The color to write stuff to host in when no (or bad) color-code was specified.

    .EXAMPLE
        Write-HostColor -String 'This is going to be <c="red">bloody red</c> text! And this is <c="green">green stuff</c> for extra color'

        Will print the specified line in multiple colors

    .EXAMPLE
        $string1 = 'This is going to be <c="red">bloody red</c> text! And this is <c="green">green stuff</c> for extra color'
        $string2 = '<c="red">bloody red</c> text! And this is <c="green">green stuff</c> for extra color'
        $string3 = 'This is going to be <c="red">bloody red</c> text! And this is <c="green">green stuff</c>'
        $string1, $string2, $string3 | Write-HostColor -DefaultColor "Magenta"

        Will print all three lines, respecting the color-codes, but use the color "Magenta" as default color.

    .EXAMPLE
        $stringLong = @"
        Dear <c="red">Sirs</c><c="green"> and</c> <c="blue">Madams</c>,

        it has come to our attention that you are not sufficiently <c="darkblue">awesome!</c>
        Kindly improve your <c="yellow">AP</c> (<c="magenta">awesome-ness points</c>) by at least 50% to maintain you membership in Awesome Inc!

        You have <c="green">27 3/4</c> days time to meet this deadline. <c="darkyellow">After this we will unfortunately be forced to rend you assunder and sacrifice your remains to the devil</c>.

        Best regards,
        <c="red">Luzifer</c>
        "@
        Write-HostColor -String $stringLong

        Will print a long multiline text in its entirety while still respecting the colorcodes
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "")]
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [string[]]
        $String,

        [ConsoleColor]
        $DefaultColor = (Get-DbatoolsConfigValue -Name "message.infocolor")
    )
    process {
        foreach ($line in $String) {
            foreach ($row in $line.Split("`n").Split([environment]::NewLine)) {
                if ($row -notlike '*<c=["'']*["'']>*</c>*') { Write-Host -Object $row -ForegroundColor $DefaultColor }
                else {
                    $match = ($row | Select-String '<c=["''](.*?)["'']>(.*?)</c>' -AllMatches).Matches
                    $index = 0
                    $count = 0

                    while ($count -le $match.Count) {
                        if ($count -lt $Match.Count) {
                            Write-Host -Object $row.SubString($index, ($match[$count].Index - $Index)) -ForegroundColor $DefaultColor -NoNewline
                            try { Write-Host -Object $match[$count].Groups[2].Value -ForegroundColor $match[$count].Groups[1].Value -NoNewline -ErrorAction Stop }
                            catch { Write-Host -Object $match[$count].Groups[2].Value -ForegroundColor $DefaultColor -NoNewline -ErrorAction Stop }

                            $index = $match[$count].Index + $match[$count].Length
                            $count++
                        } else {
                            Write-Host -Object $row.SubString($index) -ForegroundColor $DefaultColor
                            $count++
                        }
                    }
                }
            }
        }
    }
}