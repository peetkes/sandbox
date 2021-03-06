xquery version "1.0-ml";
(:~
 : This library is based on the work of miguelrgonzalez
 : The original gist can beund here: https://gist.github.com/miguelrgonzalez/d8daf7e3840f20b8dcee
 : ToDo:
 :  Handle rational value,
 :      rational is build up of a 4 byte numerator and a 4 byte denominator in teh form of numerator/denominator
 :)
module namespace exif = "http://marklogic.com/exif-parser";

import module namespace exif-consts = "http://marklogic.com/exif/consts" at "/lib/exif-consts.xqy";

declare function exif:endianness(
        $binary as binary(),
        $byte-order as xs:string
) as binary()
{
    if ($byte-order eq 'BI')
    then $binary
    else (: LI :)
        let $size := xdmp:binary-size($binary)
        let $result :=
            for $pos in (0 to $size - 1)
            return fn:string(xdmp:subbinary($binary, $size - $pos, 1))
        return binary {xs:hexBinary(fn:string-join($result, ''))}
};

declare function exif:fetch-short-or-long(
        $byte-order as xs:string,
        $count as xs:integer,
        $size as xs:integer,
        $binary as binary()
) as item()?
{
    let $short :=
        for $i in (1 to $count)
        let $value := xdmp:hex-to-integer(fn:string(xs:hexBinary(exif:endianness(xdmp:subbinary($binary, 1 + ($i - 1)*$size, $size), $byte-order))))
        return $value
    return
        if ($count > 1)
        then fn:string-join($short, ";")
        else $short
};

declare function exif:fetch-rational(
        $byte-order as xs:string,
        $count as xs:integer,
        $size as xs:integer,
        $binary as binary()
) as item()?
{
    let $rational :=
        for $i in (1 to $count)
        let $rational := binary { xdmp:subbinary($binary, 1 + ($i - 1)*$size, $size) }
        let $numerator := xdmp:hex-to-integer(fn:string(xs:hexBinary(exif:endianness(xdmp:subbinary($rational, 1, 4), $byte-order))))
        let $denominator := xdmp:hex-to-integer(fn:string(xs:hexBinary(exif:endianness(xdmp:subbinary($rational, 5, 4), $byte-order))))
        return
            if ($denominator > 0)
            then fn:string($numerator div $denominator)
            else fn:string(xs:hexBinary($rational))
    return
        if ($count > 1)
        then fn:string-join($rational, ";")
        else $rational
};

declare function exif:fetch-value(
        $binary as binary(),
        $byte-order as xs:string,
        $type as xs:integer,
        $count as xs:integer,
        $start as xs:integer,
        $offset as binary()
) as item()?
{
    let $size := $exif-consts:TYPES/type[@id eq $type]/@size
    return
        if ($count * $size > 4)
        (: if the value is bigger than 4 bytes will be stored in the data section :)
        then
            let $binary := binary { xdmp:subbinary($binary,
                    $start + xdmp:hex-to-integer(fn:string(xs:hexBinary(exif:endianness($offset, $byte-order)))),
                    $count * $size) }
            return
                if (xdmp:binary-size($binary) > 0)
                then
                    if ($exif-consts:TYPES/type[@id eq  $type and @decode eq 'true'])
                    then xdmp:binary-decode($binary, 'utf8')
                    else if ($exif-consts:TYPES/type[@id eq $type] = ("Rational","SRational"))
                    then exif:fetch-rational($byte-order, $count, $size, $binary)
                    else xs:string(fn:data($binary))
                else ''
        else
            if ($exif-consts:TYPES/type[@id eq  $type and @decode eq 'true'])
            then xdmp:binary-decode(exif:endianness($offset, $byte-order), 'utf8')
            else if ($exif-consts:TYPES/type[@id eq  $type] = ("Short", "Long"))
            then fetch-short-or-long($byte-order, $count, $size, $offset)
            else xs:string(fn:data(exif:endianness($offset, $byte-order)))
};

declare function exif:process-fields(
        $image as binary(),
        $byte-order as xs:string,
        $start as xs:integer,
        $offset as xs:integer,
        $fieldNames as map:map
) as element()*
{
    let $field-count-bin := binary { xs:hexBinary(xdmp:subbinary($image, $start + $offset, 2))}
    let $field-count := xdmp:hex-to-integer(fn:string(xs:hexBinary(exif:endianness($field-count-bin,$byte-order))))
    return (
        for $cnt in 1 to $field-count
        let $field := binary { xdmp:subbinary($image, $start + $offset + 2 + ($cnt - 1)*12, 12) }
        let $tag-id := exif:endianness(xdmp:subbinary($field, 1, 2), $byte-order)
        let $type := exif:endianness(xdmp:subbinary($field, 3, 2), $byte-order)
        let $count := xdmp:hex-to-integer(fn:string(xs:hexBinary(exif:endianness(xdmp:subbinary($field, 5, 4), $byte-order))))
        let $value-offset := xdmp:hex-to-integer(fn:string(xs:hexBinary(exif:endianness(xdmp:subbinary($field, 9, 4), $byte-order))))
        let $offset-to-value := xdmp:subbinary($field, 9, 4)
        let $fields :=
            element field {
                attribute original { xs:hexBinary($field) },
                attribute tag-id { $tag-id },
                attribute name { map:get($fieldNames, fn:string(xs:hexBinary($tag-id))) },
                attribute type { $type },
                attribute count { $count },
                attribute value-offset { $value-offset },
                exif:fetch-value($image, $byte-order, xdmp:hex-to-integer(fn:string(xs:hexBinary($type))), $count, $start, $offset-to-value)
            }
        return (
            $fields,
            if ($fields[@name eq 'ExifOffset'])
            then exif:process-fields($image, $byte-order, $start, $fields[@name eq 'ExifOffset']/@value-offset, $fieldNames)
            else (),
            if ($fields[@name eq 'GPSInfo'])
            then exif:process-fields($image, $byte-order, $start, $fields[@name eq 'GPSInfo']/@value-offset, $exif-consts:GPS-FIELDS)
            else ()
        )
    )
};

declare function exif:get-tiff-header(
        $offset as xs:integer,
        $image as binary()
) as map:map
{
    let $tiff-header-start := 9
    let $tiff-header := binary { xs:hexBinary(xdmp:subbinary($image, $tiff-header-start, 8)) }
    let $byte-order :=
        if (fn:matches(fn:string(xs:hexBinary($tiff-header)), '^4D4D.*'))
        then 'BI' (: Big indian :)
        else 'LI' (: Assume 4949 Little indian :)
    (: see http://partners.adobe.com/public/developer/en/tiff/TIFF6.pdf :)
    let $idf0-offset := xdmp:hex-to-integer(fn:string(xs:hexBinary(exif:endianness(binary { xs:hexBinary(xdmp:subbinary($tiff-header, 5, 4))}, $byte-order))))
    return map:map()
    => map:with("header", xs:hexBinary($tiff-header))
    => map:with("byte-order", $byte-order)
    => map:with("start", $tiff-header-start + $offset - 1)
    => map:with("offset", $idf0-offset)
};

