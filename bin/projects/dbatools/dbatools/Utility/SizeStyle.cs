using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Sqlcollaborative.Dbatools.Utility
{
    /// <summary>
    /// How size objects should be displayed
    /// </summary>
    public enum SizeStyle
    {
        /// <summary>
        /// The size object is styled dependend on the number stored within.
        /// </summary>
        Dynamic = 1,

        /// <summary>
        /// The size object is shown as a plain number
        /// </summary>
        Plain = 2,

        /// <summary>
        /// The size object is styled as a byte number
        /// </summary>
        Byte = 4,

        /// <summary>
        /// The size object is styled as a kilobyte number
        /// </summary>
        Kilobyte = 8,

        /// <summary>
        /// The size object is styled as a megabyte number
        /// </summary>
        Megabyte = 16,

        /// <summary>
        /// The size object is styled as a Gigabyte number
        /// </summary>
        Gigabyte = 32,

        /// <summary>
        /// The size object is styled as a Terabyte number
        /// </summary>
        Terabyte = 64
    }
}
