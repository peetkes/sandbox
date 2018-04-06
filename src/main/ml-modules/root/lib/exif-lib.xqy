xquery version "1.0-ml";

module namespace exif = "http://marklogic.com/exif";

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

declare function exif:fetch-value(
        $binary as binary(),
        $byte-order as xs:string,
        $type as xs:integer,
        $count as xs:integer,
        $start as xs:integer,
        $offset as binary()
) as item()?
{
    if ($count * $exif-consts:TYPES/type[@id eq $type]/@size > 4)
    (: if the value is bigger than 4 bytes will be stored in the data section :)
    then
        let $binary := binary { xdmp:subbinary($binary,
                $start + xdmp:hex-to-integer(fn:string(xs:hexBinary(exif:endianness($offset, $byte-order)))),
                $count * $exif-consts:TYPES/type[@id eq $type]/@size) }
        return
            if (xdmp:binary-size($binary) > 0)
            then
                if ($exif-consts:TYPES/type[@id eq  $type and @decode eq 'true'])
                then xdmp:binary-decode($binary, 'utf8')
                else xs:string(fn:data($binary))
            else ''
    else
        if ($exif-consts:TYPES/type[@id eq  $type and @decode eq 'true'])
        then xdmp:binary-decode($offset, 'utf8')
        else xs:string(fn:data($offset))
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

