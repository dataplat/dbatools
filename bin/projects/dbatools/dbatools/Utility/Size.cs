using System;

namespace Sqlcollaborative.Dbatools.Utility
{
    /// <summary>
    /// Class that reports File size.
    /// </summary>
    [Serializable]
    public class Size : IComparable<Size>, IComparable
    {
        /// <summary>
        /// Number of bytes contained in whatever object uses this object as a property
        /// </summary>
        public long Byte { get; set; }

        /// <summary>
        /// Kilobyte representation of the bytes
        /// </summary>
        public double Kilobyte
        {
            get
            {
                return (Byte / 1024d);
            }
        }

        /// <summary>
        /// Megabyte representation of the bytes
        /// </summary>
        public double Megabyte
        {
            get
            {
                return (Byte / 1048576d);
            }
        }

        /// <summary>
        /// Gigabyte representation of the bytes
        /// </summary>
        public double Gigabyte
        {
            get
            {
                return (Byte / 1073741824d);
            }
        }

        /// <summary>
        /// Terabyte representation of the bytes
        /// </summary>
        public double Terabyte
        {
            get
            {
                return (Byte / 1099511627776d);
            }
        }

        /// <summary>
        /// Number if digits behind the dot.
        /// </summary>
        public int? Digits
        {
            get
            {
                return _digits ?? UtilityHost.SizeDigits;
            }
            set
            {
                _digits = value == null ? null : (value.Value <= 0 ? 0 : value);
            }
        }
        private int? _digits;

        /// <summary>
        /// How the size object should be displayed.
        /// </summary>
        public SizeStyle? Style
        {
            get
            {
                return _style ?? UtilityHost.SizeStyle;
            }
            set
            {
                _style = value;
            }
        }
        private SizeStyle? _style;

        /// <summary>
        /// Shows the default string representation of size
        /// </summary>
        /// <returns></returns>
        public override string ToString()
        {
            string format = "{0:N" + Digits + "} {1}";
            switch (Style)
            {
                case SizeStyle.Plain:
                    return Byte.ToString();
                case SizeStyle.Byte:
                    return (String.Format("{0} {1}", Byte, "B"));
                case SizeStyle.Kilobyte:
                    return (String.Format(format, Kilobyte, "KB"));
                case SizeStyle.Megabyte:
                    return (String.Format(format, Megabyte, "MB"));
                case SizeStyle.Gigabyte:
                    return (String.Format(format, Gigabyte, "GB"));
                case SizeStyle.Terabyte:
                    return (String.Format(format, Terabyte, "TB"));
                default:
                    if (Terabyte > 1)
                    {
                        return (String.Format(format, Terabyte, "TB"));
                    }
                    if (Gigabyte > 1)
                    {
                        return (String.Format(format, Gigabyte, "GB"));
                    }
                    if (Megabyte > 1)
                    {
                        return (String.Format(format, Megabyte, "MB"));
                    }
                    if (Kilobyte > 1)
                    {
                        return (String.Format(format, Kilobyte, "KB"));
                    }
                    if (Byte > -1)
                    {
                        return (String.Format("{0} {1}", Byte, "B"));
                    }
                    if (Byte == -1)
                        return "Unlimited";
                    return "";
            }
        }

        /// <summary>
        /// Simple equality test
        /// </summary>
        /// <param name="obj">The object to test it against</param>
        /// <returns>True if equal, false elsewise</returns>
        public override bool Equals(object obj)
        {
            var size = obj as Size;
            return (size != null  && (Byte == size.Byte));
        }

        /// <inheritdoc cref="Int64.GetHashCode"/>
        /// <remarks>The hashcode of the underlying size</remarks>
        public override int GetHashCode()
        {
            // ReSharper disable once NonReadonlyMemberInGetHashCode
            return Byte.GetHashCode();
        }

        /// <summary>
        /// Creates an empty size.
        /// </summary>
        public Size()
        {

        }

        /// <summary>
        /// Creates a size with some content
        /// </summary>
        /// <param name="Byte">The length in bytes to set the size to</param>
        public Size(long Byte)
        {
            this.Byte = Byte;
        }

        /// <inheritdoc cref="IComparable{Size}.CompareTo"/>
        /// <remarks>For sorting</remarks>
        public int CompareTo(Size obj)
        {
            return Byte.CompareTo(obj.Byte);
        }

        /// <inheritdoc cref="IComparable.CompareTo"/>
        /// <remarks>For sorting</remarks>
        /// <exception cref="ArgumentException">If you compare with something invalid.</exception>
        public int CompareTo(object obj)
        {
            var size = obj as Size;
            if (size != null)
            {
                return CompareTo(size);
            }
            throw new ArgumentException(String.Format("Cannot compare a {0} to a {1}", typeof(Size).FullName, obj.GetType().FullName));
        }

        #region MathOperators
        /// <summary>
        /// Adds two sizes
        /// </summary>
        /// <param name="a">The first size to add</param>
        /// <param name="b">The second size to add</param>
        /// <returns>The sum of both sizes</returns>
        public static Size operator +(Size a, Size b)
        {
            return new Size(a.Byte + b.Byte);
        }

        /// <summary>
        /// Substracts two sizes
        /// </summary>
        /// <param name="a">The first size to substract</param>
        /// <param name="b">The second size to substract</param>
        /// <returns>The difference between both sizes</returns>
        public static Size operator -(Size a, Size b)
        {
            return new Size(a.Byte - b.Byte);
        }

        /// <summary>
        /// Multiplies two sizes with each other
        /// </summary>
        /// <param name="a">The size to multiply</param>
        /// <param name="b">The size to multiply with</param>
        /// <returns>A multiplied size.</returns>
        public static Size operator *(Size a, double b)
        {
            return new Size((long)(a.Byte * b));
        }

        /// <summary>
        /// Divides one size by another. 
        /// </summary>
        /// <param name="a">The size to divide</param>
        /// <param name="b">The size to divide with</param>
        /// <returns>Divided size (note: Cut off)</returns>
        public static Size operator /(Size a, double b)
        {
            return new Size((long)((double)a.Byte / b));
        }

        /// <summary>
        /// Multiplies two sizes with each other
        /// </summary>
        /// <param name="a">The size to multiply</param>
        /// <param name="b">The size to multiply with</param>
        /// <returns>A multiplied size.</returns>
        public static Size operator *(Size a, Size b)
        {
            return new Size(a.Byte * b.Byte);
        }

        /// <summary>
        /// Divides one size by another.
        /// </summary>
        /// <param name="a">The size to divide</param>
        /// <param name="b">The size to divide with</param>
        /// <returns>Divided size (note: Cut off)</returns>
        public static Size operator /(Size a, Size b)
        {
            return new Size((long)((double)a.Byte / (double)b.Byte));
        }

        #endregion
        #region ImplicitCasts

        /// <summary>
        /// Implicitly converts int to size
        /// </summary>
        /// <param name="a">The number to convert</param>
        public static implicit operator Size(int a)
        {
            return new Size(a);
        }

        /// <summary>
        /// Implicitly converts int to size
        /// </summary>
        /// <param name="a">The number to convert</param>
        public static implicit operator Size(decimal a)
        {
            return new Size((long)a);
        }

        /// <summary>
        /// Implicitly converts size to int
        /// </summary>
        /// <param name="a">The size to convert</param>
        public static implicit operator Int32(Size a)
        {
            return (Int32)a.Byte;
        }

        /// <summary>
        /// Implicitly converts long to size
        /// </summary>
        /// <param name="a">The number to convert</param>
        public static implicit operator Size(long a)
        {
            return new Size(a);
        }

        /// <summary>
        /// Implicitly converts size to long
        /// </summary>
        /// <param name="a">The size to convert</param>
        public static implicit operator Int64(Size a)
        {
            return a.Byte;
        }

        /// <summary>
        /// Implicitly converts string to size
        /// </summary>
        /// <param name="a">The string to convert</param>
        public static implicit operator Size(String a)
        {
            return new Size(Int64.Parse(a));
        }

        /// <summary>
        /// Implicitly converts double to size
        /// </summary>
        /// <param name="a">The number to convert</param>
        public static implicit operator Size(double a)
        {
            return new Size((long)a);
        }

        /// <summary>
        /// Implicitly converts size to double
        /// </summary>
        /// <param name="a">The size to convert</param>
        public static implicit operator double(Size a)
        {
            return a.Byte;
        }
        #endregion Operators
    }
}