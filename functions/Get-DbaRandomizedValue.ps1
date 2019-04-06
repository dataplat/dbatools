function Get-DbaRandomizedValue {
    <#
    .SYNOPSIS
        This function will generate a random value for a specific data type or bogus type and subtype

    .DESCRIPTION
        Generates a random value based on the assigned sql data type or bogus type with sub type.
        It supports a wide range of sql data types and an entire dictionary of various random values.

    .PARAMETER DataType
        The target SQL Server instance or instances.

        Supported data types are bigint, bit, bool, char, date, datetime, datetime2, decimal, int, float, guid, money, numeric, nchar, ntext, nvarchar, real, smalldatetime, smallint, text, time, tinyint, uniqueidentifier, userdefineddatatype, varchar

    .PARAMETER RandomizerType
        Bogus type to use.

        Supported types are Address, Commerce, Company, Database, Date, Finance, Hacker, Hashids, Image, Internet, Lorem, Name, Person, Phone, Random, Rant, System

    .PARAMETER RandomizerSubType
        Subtype to use.

    .PARAMETER Min
        Minimum value used to generate certain lengths of values. Default is 0

    .PARAMETER Max
        Maximum value used to generate certain lengths of values. Default is 255

    .PARAMETER Precision
        Precision used for numeric sql data types like decimal, numeric, real and float

    .PARAMETER CharacterString
        The characters to use in string data. 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789' by default

    .PARAMETER Format
        Use specilized formatting with certain randomizer types like phone number.

    .PARAMETER Symbol
        Use a symbol in front of the value i.e. $100,12

    .PARAMETER Locale
        Set the local to enable certain settings in the masking. The default is 'en'

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: DataMasking, DataGeneration
        Author: Sander Stad (@sqlstad, sqlstad.nl)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaRandomizedValue

    .EXAMPLE
        Get-DbaRandomizedValue -DataType bit

        Will return either a 1 or 0

    .EXAMPLE
        Get-DbaRandomizedValue -DataType int

        Will generate a number between -2147483648 and 2147483647

    .EXAMPLE
        Get-DbaRandomizedValue -RandomizerSubType Zipcode

        Generates a random zipcode

    .EXAMPLE
        Get-DbaRandomizedValue -RandomizerSubType Zipcode -Format "#### ##"

        Generates a random zipcode like "1234 56"

    .EXAMPLE
        Get-DbaRandomizedValue -RandomizerSubType PhoneNumber -Format "(###) #######"

        Generates a random phonenumber like "(123) 4567890"

    #>
    [CmdLetBinding()]
    param(
        [string]$DataType,
        [string]$RandomizerType,
        [string]$RandomizerSubType,
        [int64]$Min = 1,
        [int64]$Max = 255,
        [int]$Precision = 2,
        [string]$CharacterString = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',
        [string]$Format,
        [string]$Symbol,
        [string]$Locale = 'en',
        [switch]$EnableException
    )


    begin {
        # Get all the random possibilities
        $randomizerTypes = Import-Csv (Resolve-Path -Path "$script:PSModuleRoot\bin\randomizer\en.randomizertypes.csv") | Group-Object { $_.Type }

        # Create the faker objects
        $typePath = Resolve-Path -Path "$script:PSModuleRoot\bin\randomizer\Bogus.dll"

        if ([AppDomain]::CurrentDomain.GetAssemblies().Location -notcontains $typePath.Path) {
            Write-Message -Level Verbose -Message "Randomizer type not loaded yet. Loading it"
            try {
                Add-Type -Path (Resolve-Path -Path $typePath)
            } catch {
                Stop-Function -Message "Couldn't load randomizer dll" -Target $typePath -ErrorRecord $_ -Continue
            }
        }

        # Create faker object
        $faker = New-Object Bogus.Faker($Locale)

        $supportedDataTypes = 'bigint', 'bit', 'bool', 'char', 'date', 'datetime', 'datetime2', 'decimal', 'int', 'float', 'guid', 'money', 'numeric', 'nchar', 'ntext', 'nvarchar', 'real', 'smalldatetime', 'smallint', 'text', 'time', 'tinyint', 'uniqueidentifier', 'userdefineddatatype', 'varchar'

        # Check the variables
        if (-not $DataType -and -not $RandomizerType -and -not $RandomizerSubType) {
            Stop-Function -Message "Please use one of the variables i.e. -DataType, -RandomizerType or -RandomizerSubType" -Continue
        } elseif ($DataType -and ($RandomizerType -or $RandomizerSubType)) {
            Stop-Function -Message "You cannot use -DataType with -RandomizerType or -RandomizerSubType" -Continue
        } elseif (-not $RandomizerSubType -and $RandomizerType) {
            Stop-Function -Message "Please enter a sub type" -Continue
        } elseif (-not $RandomizerType -and $RandomizerSubType) {
            $RandomizerType = $randomizerTypes.Group | Where-Object Subtype -eq $RandomizerSubType | Select-Object Type -ExpandProperty Type -First 1
        }

        if ($DataType -and $DataType.ToLower() -notin $supportedDataTypes) {
            Stop-Function -Message "Unsupported sql data type" -Continue -Target $DataType
        }

        # Check the bogus type
        if ($RandomizerType) {
            if ($RandomizerType -notin ($randomizerTypes.Group.Type | Select-Object -Unique)) {
                Stop-Function -Message "Invalid randomizer type" -Continue -Target $RandomizerType
            }
        }

        # Check the sub type
        if ($RandomizerSubType) {
            if ($RandomizerSubType -notin ($randomizerTypes.Group.SubType | Select-Object -Unique)) {
                Stop-Function -Message "Invalid randomizer sub type" -Continue -Target $RandomizerSubType
            }

            $randomizerSubTypes = $randomizerTypes.Group | Where-Object Type -eq $RandomizerType | Select-Object SubType -ExpandProperty SubType

            if ($RandomizerSubType -notin $randomizerSubTypes) {
                Stop-Function -Message "Invalid randomizer type with sub type combination" -Continue -Target $RandomizerSubType
            }
        }

        if ($Min -gt $Max) {
            Stop-Function -Message "Min value cannot be greater than max value" -Continue -Target $Min
        }
    }

    process {

        if (Test-FunctionInterrupt) { return }

        if ($DataType) {

            switch ($DataType.ToLower()) {
                'bigint' {
                    if ($Min -lt -9223372036854775808) {
                        $Min = -9223372036854775808
                        Write-Message -Level Verbose -Message "Min value for data type is too small. Reset to $Min"
                    }

                    if ($Max -gt 9223372036854775807) {
                        $Max = 9223372036854775807
                        Write-Message -Level Verbose -Message "Max value for data type is too big. Reset to $Max"
                    }
                }

                { $psitem -in 'bit', 'bool' } {
                    if ($faker.System.Random.Bool()) {
                        1
                    } else {
                        0
                    }
                }
                'date' {
                    if ($Min -or $Max) {
                        ($faker.Date.Between($Min, $Max)).ToString("yyyyMMdd")
                    } else {
                        ($faker.Date.Past()).ToString("yyyyMMdd")
                    }
                }
                { $psitem -in 'datetime', 'datetime2', 'smalldatetime' } {
                    if ($Min -or $Max) {
                        ($faker.Date.Between($Min, $Max)).ToString("yyyy-MM-dd HH:mm:ss.fffffff")
                    } else {
                        ($faker.Date.Past()).ToString("yyyy-MM-dd HH:mm:ss.fffffff")
                    }
                }
                { $psitem -in 'decimal', 'float', 'money', 'numeric', 'real' } {
                    $faker.Finance.Amount($Min, $Max, $Precision)
                }
                'int' {
                    if ($Min -lt -2147483648) {
                        $Min = -2147483648
                        Write-Message -Level Verbose -Message "Min value for data type is too small. Reset to $Min"
                    }

                    if ($Max -gt 2147483647) {
                        $Max = 2147483647
                        Write-Message -Level Verbose -Message "Max value for data type is too big. Reset to $Max"
                    }

                    $faker.System.Random.Int($Min, $Max)

                }
                'smallint' {
                    if ($Min -lt -32768) {
                        $Min = 32768
                        Write-Message -Level Verbose -Message "Min value for data type is too small. Reset to $Min"
                    }

                    if ($Max -gt 32767) {
                        $Max = 32767
                        Write-Message -Level Verbose -Message "Max value for data type is too big. Reset to $Max"
                    }

                    $faker.System.Random.Int($Min, $Max)
                }
                'time' {
                    ($faker.Date.Past()).ToString("HH:mm:ss.fffffff")
                }
                'tinyint' {
                    if ($Min -lt 0) {
                        $Min = 0
                        Write-Message -Level Verbose -Message "Min value for data type is too small. Reset to $Min"
                    }

                    if ($Max -gt 255) {
                        $Max = 255
                        Write-Message -Level Verbose -Message "Max value for data type is too big. Reset to $Max"
                    }

                    $faker.System.Random.Int($Min, $Max)
                }
                { $psitem -in 'uniqueidentifier', 'guid' } {
                    $faker.System.Random.Guid().Guid
                }
                'userdefineddatatype' {
                    if ($Max -eq 1) {
                        if ($faker.System.Random.Bool()) {
                            1
                        } else {
                            0
                        }
                    } else {
                        $null
                    }
                }
                { $psitem -in 'char', 'nchar', 'nvarchar', 'varchar' } {
                    $faker.Random.String2($Min, $Max, $CharacterString)
                }

            }

        } else {

            $randSubType = $RandomizerSubType.ToLower()

            switch ($RandomizerType.ToLower()) {
                'address' {

                    if ($randSubType -in 'latitude', 'longitude') {
                        $faker.Address.Latitude($Min, $Max)
                    } elseif ($randSubType -eq 'zipcode') {
                        if ($Format) {
                            $faker.Address.ZipCode("$($Format)")
                        } else {
                            $faker.Address.ZipCode()
                        }
                    } else {
                        $faker.Address.$RandomizerSubType()
                    }

                }
                'commerce' {
                    if ($randSubType -eq 'categories') {
                        $faker.Commerce.Categories($Max)
                    } elseif ($randSubType -eq 'departments') {
                        $faker.Commerce.Department($Max)
                    } elseif ($randSubType -eq 'price') {
                        $faker.Commerce.Price($min, $Max, $Precision, $Symbol)
                    } else {
                        $faker.Commerce.$RandomizerSubType()
                    }

                }
                'company' {
                    $faker.Company.$RandomizerSubType()
                }
                'database' {
                    $faker.Database.$RandomizerSubType()
                }
                'date' {
                    if ($randSubType -eq 'past') {
                        $faker.Date.Past().ToString("yyyy-MM-dd HH:mm:ss.fffffff")
                    } elseif ($randSubType -eq 'future') {
                        $faker.Future.Past().ToString("yyyy-MM-dd HH:mm:ss.fffffff")
                    } elseif ($randSubType -eq 'recent') {
                        $faker.Recent.Past().ToString("yyyy-MM-dd HH:mm:ss.fffffff")
                    } else {
                        $faker.Date.$RandomizerSubType()
                    }


                }
                'finance' {
                    if ($randSubType -eq 'account') {
                        $faker.Finance.Account($Max)
                    } elseif ($randSubType -eq 'amount') {
                        $faker.Finance.Amount($Min, $Max, $Precision)
                    } else {
                        $faker.Finance.$RandomizerSubType()
                    }
                }
                'hacker' {
                    $faker.Hacker.$RandomizerSubType()
                }
                'image' {
                    $faker.Image.$RandomizerSubType()
                }
                'internet' {
                    if ($randSubType -eq 'password') {
                        $faker.Internet.Password($Max)
                    } else {
                        $faker.Internet.$RandomizerSubType()
                    }
                }
                'lorem' {
                    if ($randSubType -eq 'paragraph') {
                        if ($Min -lt 1) {
                            $Min = 1
                            Write-Message -Level Verbose -Message "Min value for sub type is too small. Reset to $Min"
                        }

                        $faker.Lorem.Paragraph($Min)

                    } elseif ($randSubType -eq 'paragraphs') {
                        if ($Min -lt 1) {
                            $Min = 1
                            Write-Message -Level Verbose -Message "Min value for sub type is too small. Reset to $Min"
                        }

                        $faker.Lorem.Paragraphs($Min)

                    } elseif ($randSubType -eq 'letter') {
                        $faker.Lorem.Letter($Max)
                    } elseif ($randSubType -eq 'lines') {
                        $faker.Lorem.Lines($Max)
                    } elseif ($randSubType -eq 'sentence') {
                        if ($Min -lt 1) {
                            $Min = 1
                            Write-Message -Level Verbose -Message "Min value for sub type is too small. Reset to $Min"
                        }

                        $faker.Lorem.Sentence($Min, $Max)

                    } elseif ($randSubType -eq 'sentences') {
                        if ($Min -lt 1) {
                            $Min = 1
                            Write-Message -Level Verbose -Message "Min value for sub type is too small. Reset to $Min"
                        }

                        $faker.Lorem.Sentences($Min, $Max)

                    } elseif ($randSubType -eq 'slug') {
                        $faker.Lorem.Slug($Max)
                    } elseif ($randSubType -eq 'words') {
                        $faker.Lorem.Words($Max)
                    } else {
                        $faker.Lorem.$RandomizerSubType()
                    }
                }
                'name' {
                    $faker.Name.$RandomizerSubType()
                }
                'person' {
                    $faker.Person.$RandomizerSubType
                }
                'phone' {
                    if ($Format) {
                        $faker.Phone.PhoneNumber($Format)
                    } else {
                        $faker.Phone.PhoneNumber()
                    }
                }
                'random' {
                    if ($randSubType -in 'byte', 'char', 'decimal', 'double', 'even', 'float', 'int', 'long', 'number', 'odd', 'sbyte', 'short', 'uint', 'ulong', 'ushort') {
                        $faker.Random.$RandomizerSubType($Min, $Max)
                    } elseif ($randSubType -eq 'bytes') {
                        $faker.Random.Bytes($Max)
                    } elseif ($randSubType -eq 'string2') {
                        $faker.Random.$RandomizerSubType($Min, $Max, $CharacterString)
                    } else {
                        $faker.Random.$RandomizerSubType()
                    }
                }
                'rant' {
                    if ($randSubType -eq 'reviews') {
                        $faker.Rant.Review($faker.Commerce.Product())
                    } elseif ($randSubType -eq 'reviews') {
                        $faker.Rant.Reviews($faker.Commerce.Product(), $Max)
                    }
                }
                'system' {
                    $faker.System.$RandomizerSubType()
                }
            }
        }
    }
}