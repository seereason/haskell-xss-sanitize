{-# LANGUAGE OverloadedStrings, TemplateHaskell #-}
-- | Sanatize HTML to prevent XSS attacks.
--
-- See README.md <http://github.com/gregwebs/haskell-xss-sanitize> for more details.
module Text.HTML.SanitizeXSS
    (
    -- * Sanitize
      sanitize
    , sanitizeBalance
    , sanitizeXSS

    -- * Custom filtering
    , filterTags
    , safeTags
    , safeTagsCustom
    , balanceTags

    -- * Utilities
    , safeTagName
    , sanitizeAttribute
    , sanitaryURI
    ) where

import Text.HTML.SanitizeXSS.Css

import Text.HTML.TagSoup

import Data.Set as Set (Set(), map, member, notMember, (\\), fromList, fromAscList)
import Data.Char ( toLower )
import Data.List (sort)
import Data.Monoid ((<>))
import Data.Text (Text, words)
import qualified Data.Text as T
import Language.Haskell.TH.Lift (lift)

import Network.URI ( parseURIReference, URI (..),
                     isAllowedInURI, escapeURIString, uriScheme )
import Codec.Binary.UTF8.String ( encodeString )

import Data.Maybe (mapMaybe)


-- | Sanitize HTML to prevent XSS attacks.  This is equivalent to @filterTags safeTags@.
sanitize :: Text -> Text
sanitize = sanitizeXSS

-- | alias of sanitize function
sanitizeXSS :: Text -> Text
sanitizeXSS = filterTags safeTags

-- | Sanitize HTML to prevent XSS attacks and also make sure the tags are balanced.
--   This is equivalent to @filterTags (balanceTags . safeTags)@.
sanitizeBalance :: Text -> Text
sanitizeBalance = filterTags (balanceTags . safeTags)

-- | Filter which makes sure the tags are balanced.  Use with 'filterTags' and 'safeTags' to create a custom filter.
balanceTags :: [Tag Text] -> [Tag Text]
balanceTags = balance []

-- | Parse the given text to a list of tags, apply the given filtering
-- function, and render back to HTML. You can insert your own custom
-- filtering, but make sure you compose your filtering function with
-- 'safeTags' or 'safeTagsCustom'.
filterTags :: ([Tag Text] -> [Tag Text]) -> Text -> Text
filterTags f = renderTagsOptions renderOptions {
    optMinimize = \x -> x `member` voidElems -- <img><img> converts to <img />, <a/> converts to <a></a>
  } .  f . canonicalizeTags . parseTags

voidElems :: Set T.Text
voidElems = fromAscList $ T.words $ T.pack "area base br col command embed hr img input keygen link meta param source track wbr"

balance :: [Text] -- ^ unclosed tags
        -> [Tag Text] -> [Tag Text]
balance unclosed [] = fmap TagClose $ filter (`notMember` voidElems) unclosed
balance (x:xs) tags'@(TagClose name:tags)
    | x == name = TagClose name : balance xs tags
    | x `member` voidElems = balance xs tags'
    | otherwise = TagOpen name [] : TagClose name : balance (x:xs) tags
balance unclosed (TagOpen name as : tags) =
    TagOpen name as : balance (name : unclosed) tags
balance unclosed (t:ts) = t : balance unclosed ts

-- | Filters out unsafe tags and sanitizes attributes. Use with
-- filterTags to create a custom filter.
safeTags :: [Tag Text] -> [Tag Text]
safeTags = safeTagsCustom safeTagName sanitizeAttribute

-- | Filters out unsafe tags and sanitizes attributes, like
-- 'safeTags', but uses custom functions for determining which tags
-- are safe and for sanitizing attributes. This allows you to add or
-- remove specific tags or attributes on the white list, or to use
-- your own white list.
--
-- @safeTagsCustom safeTagName sanitizeAttribute@ is equivalent to
-- 'safeTags'.
--
-- @since 0.3.6
safeTagsCustom ::
     (Text -> Bool)                       -- ^ Select safe tags, like
                                          -- 'safeTagName'
  -> ((Text, Text) -> Maybe (Text, Text)) -- ^ Sanitize attributes,
                                          -- like 'sanitizeAttribute'
  -> [Tag Text] -> [Tag Text]
safeTagsCustom _ _ [] = []
safeTagsCustom safeName sanitizeAttr (t@(TagClose name):tags)
    | safeName name = t : safeTagsCustom safeName sanitizeAttr tags
    | otherwise = safeTagsCustom safeName sanitizeAttr tags
safeTagsCustom safeName sanitizeAttr (TagOpen name attributes:tags)
  | safeName name = TagOpen name (mapMaybe sanitizeAttr attributes) :
      safeTagsCustom safeName sanitizeAttr tags
  | otherwise = safeTagsCustom safeName sanitizeAttr tags
safeTagsCustom n a (t:tags) = t : safeTagsCustom n a tags

safeTagName :: Text -> Bool
safeTagName tagname = tagname `member` sanitaryTags

safeAttribute :: (Text, Text) -> Bool
safeAttribute (name, value) = name `member` sanitaryAttributes &&
  (name `notMember` uri_attributes || sanitaryURI value)

-- | low-level API if you have your own HTML parser. Used by safeTags.
sanitizeAttribute :: (Text, Text) -> Maybe (Text, Text)
sanitizeAttribute ("style", value) =
    let css = sanitizeCSS value
    in  if T.null css then Nothing else Just ("style", css)
sanitizeAttribute attr | safeAttribute attr = Just attr
                       | otherwise = Nothing


-- | Returns @True@ if the specified URI is not a potential security risk.
sanitaryURI :: Text -> Bool
sanitaryURI u =
  case parseURIReference (escapeURI $ T.unpack u) of
     Just p  -> (null (uriScheme p)) ||
                ((fmap toLower $ init $ uriScheme p) `member` safeURISchemes)
     Nothing -> False


-- | Escape unicode characters in a URI.  Characters that are
-- already valid in a URI, including % and ?, are left alone.
escapeURI :: String -> String
escapeURI = escapeURIString isAllowedInURI . encodeString

safeURISchemes :: Set String
safeURISchemes = Set.map T.unpack acceptable_protocols

sanitaryTags :: Set Text
sanitaryTags = (acceptable_elements <> mathml_elements <> svg_elements)
  \\ svg_allow_local_href -- extra filtering not implemented

sanitaryAttributes :: Set Text
sanitaryAttributes = (allowed_html_uri_attributes <> acceptable_attributes <> mathml_attributes <> svg_attributes)
  \\ svg_attr_val_allows_ref -- extra unescaping not implemented

allowed_html_uri_attributes :: Set Text
allowed_html_uri_attributes = fromAscList $(lift $ sort $ T.words "href src cite action longdesc")

uri_attributes :: Set Text
uri_attributes = allowed_html_uri_attributes <> fromAscList $(lift $ sort $ T.words "xlink:href xml:base")

acceptable_elements :: Set Text
acceptable_elements = fromAscList $(lift $ sort $ T.words "a abbr acronym address area article aside audio b big blockquote br button canvas caption center cite code col colgroup command datagrid datalist dd del details dfn dialog dir div dl dt em event-source fieldset figcaption figure footer font form header h1 h2 h3 h4 h5 h6 hr i img input ins keygen kbd label legend li m main map menu meter multicol nav nextid ol output optgroup option p pre progress q s samp section select small sound source spacer span strike strong sub sup table tbody td textarea time tfoot th thead tr tt u ul var video")
  
mathml_elements :: Set Text
mathml_elements = fromAscList $(lift $ sort $ T.words "maction math merror mfrac mi mmultiscripts mn mo mover mpadded mphantom mprescripts mroot mrow mspace msqrt mstyle msub msubsup msup mtable mtd mtext mtr munder munderover none")

-- this should include altGlyph I think
svg_elements :: Set Text
svg_elements = fromAscList $(lift $ sort $ T.words "a animate animateColor animateMotion animateTransform clipPath circle defs desc ellipse font-face font-face-name font-face-src g glyph hkern linearGradient line marker metadata missing-glyph mpath path polygon polyline radialGradient rect set stop svg switch text title tspan use")
  
-- "data", TODO: allow this with further filtering
 -- "style" gets further filtering
acceptable_attributes :: Set Text
acceptable_attributes = fromAscList $(lift $ sort $ T.words "abbr accept accept-charset accesskey align alt autocomplete autofocus axis background balance bgcolor bgproperties border bordercolor bordercolordark bordercolorlight bottompadding cellpadding cellspacing ch challenge char charoff choff charset checked class clear color cols colspan compact contenteditable controls coords datafld datapagesize datasrc datetime default delay dir disabled draggable dynsrc enctype end face for form frame galleryimg gutter headers height hidefocus hidden high hreflang hspace icon id inputmode ismap keytype label leftspacing lang list loop loopcount loopend loopstart low lowsrc max maxlength media method min multiple name nohref noshade nowrap open optimum pattern ping point-size prompt pqg radiogroup readonly rel repeat-max repeat-min replace required rev rightspacing rows rowspan rules scope selected shape size span start step style summary suppress tabindex target template title toppadding type unselectable usemap urn valign value variable volume vspace vrml width wrap xml:lang")

acceptable_protocols :: Set Text
acceptable_protocols = fromAscList $(lift $ sort $ T.words  "ed2k ftp http https irc mailto news gopher nntp telnet webcal xmpp callto feed urn aim rsync tag ssh sftp rtsp afs")

mathml_attributes :: Set Text
mathml_attributes = fromAscList $(lift $ sort $ T.words "actiontype align columnalign columnalign columnalign columnlines columnspacing columnspan depth display displaystyle equalcolumns equalrows fence fontstyle fontweight frame height linethickness lspace mathbackground mathcolor mathvariant mathvariant maxsize minsize other rowalign rowalign rowalign rowlines rowspacing rowspan rspace scriptlevel selection separator stretchy width width xlink:href xlink:show xlink:type xmlns xmlns:xlink")

svg_attributes :: Set Text
svg_attributes = fromAscList $(lift $ sort $ T.words "accent-height accumulate additive alphabetic arabic-form ascent attributeName attributeType baseProfile bbox begin by calcMode cap-height class clip-path color color-rendering content cx cy d dx dy descent display dur end fill fill-opacity fill-rule font-family font-size font-stretch font-style font-variant font-weight from fx fy g1 g2 glyph-name gradientUnits hanging height horiz-adv-x horiz-origin-x id ideographic k keyPoints keySplines keyTimes lang marker-end marker-mid marker-start markerHeight markerUnits markerWidth mathematical max min name offset opacity orient origin overline-position overline-thickness panose-1 path pathLength points preserveAspectRatio r refX refY repeatCount repeatDur requiredExtensions requiredFeatures restart rotate rx ry slope stemh stemv stop-color stop-opacity strikethrough-position strikethrough-thickness stroke stroke-dasharray stroke-dashoffset stroke-linecap stroke-linejoin stroke-miterlimit stroke-opacity stroke-width systemLanguage target text-anchor to transform type u1 u2 underline-position underline-thickness unicode unicode-range units-per-em values version viewBox visibility width widths x x-height x1 x2 xlink:actuate xlink:arcrole xlink:href xlink:role xlink:show xlink:title xlink:type xml:base xml:lang xml:space xmlns xmlns:xlink y y1 y2 zoomAndPan")

-- the values for these need to be escaped
svg_attr_val_allows_ref :: Set Text
svg_attr_val_allows_ref = fromAscList $(lift $ sort $ T.words "clip-path color-profile cursor fill filter marker marker-start marker-mid marker-end mask stroke")

svg_allow_local_href :: Set Text
svg_allow_local_href = fromAscList $(lift $ sort $ T.words "altGlyph animate animateColor animateMotion animateTransform cursor feImage filter linearGradient pattern radialGradient textpath tref set use")

