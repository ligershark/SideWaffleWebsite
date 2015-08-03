using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

namespace SideWaffleWebsite5.Models
{
    public class Template
    {
        /// <summary>
        /// Represents a single template found within the SideWaffle extension.
        ///
        /// Note: This data is pulled from the template-report.xml file that is
        /// uploaded in each GitHub release.
        /// </summary>
        public string Name { get; set; }
        public string Category { get; set; }
    }
}