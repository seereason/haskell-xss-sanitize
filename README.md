Summary
=======
provides a function Text.HTML.SanitizeXSS.sanitizeXSS that filters html to prevent XSS attacks.

Use Case
========
All html from an untrusted source (user of a web application) should be ran through this function.
If you trust the html (you wrote it), you do not need to use this.

Detail
========
This is not escaping! Escaping html does prevents XSS attacks. Strings should be html escaped to show up properly and to prevent XSS attacks. However, escaping will ruin the display of the html.

This function removes any tags or attributes that are not in its white-list of. This may sound picky, but most html should make it through unchanged, making the proces unnoticeable to the user but giving us safe html. 

Integration
===========
It is recommended to integrate this so that it is automatically used whenever an application receives untrusted html data (instead of before it is displayed). See the Yesod web framework as an example.

Credit
===========
This was taken from John MacFarlane's Pandoc (with permission) modified to be faster and parsing redone with TagSoup. html5lib is also being used as a reference (BSD style license).


Limitations
===========

TagSoup Parser
--------------
TagSoup is used to parse the HTML, and it does a good job. However TagSoup does not maintain all white space. TagSoup does not distinguish between the following cases:

    <a href="foo">, <a href=foo>
    <a   href>, <a href>
    <a></a>, <a/>

In the third case, img and br tags will be output as a single self-closing tags. Other self-closing tags will be output as an open and closing pair. So `<img /> or <img><img>` converts to `<img />`, and `<a></a> or <a/>` converts to `<a></a>`.  There are future updates to TagSoup planned so that TagSoup will be able to render tags exactly the same as they were parsed.

Where is the white list from?
-----------------------------
Ultimately this is where your security comes from, although I would tend to think that even a basic, incomplete white list would act as a strong deterrent.

Version 0.1 of the white list is from Pandoc. Probably that list is from an older version of (a wiki page containing a white list)[http://wiki.whatwg.org/wiki/Sanitization_rules]. Having some prior experience editing Wikipedia, I am a little wary of directly using a wiki for a purpose like this, although it does seem to be watched over.

Version >= 0.2 uses (the source code of html5lib)[http://code.google.com/p/html5lib/source/browse/python/html5lib/sanitizer.py]. as the source of the white list and my implementation reference. They do reference that wiki page as their source, but hopefully they are careful of when they import it into their code. I would definitely consider working with the maintatiners of html5lib, but it doesn't make sense to merge the projects because sanitization is just one aspect of html5lib (They have a parser also)

If anyone knows of better sources or thinks a particular tag/attribute/value may be vulerable, please let me know.

attributes data and style
-------------------------
The href attribute is white listed, but its value must pass through a white list also. This is how the data and style attributes should work also. However, this was never implemented in Pandoc, and the html5lib code is a little complicated and relies on regular expressions that I don't understand. So for now thes attributes are not on the white list.

svg and mathml
--------------
A mathml white list is fully implemented.
There is a white list for svg elements and attributes. However, some elements are not included because they need further filtering (just like the data and style html attributes)