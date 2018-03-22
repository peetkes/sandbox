'use strict';
declareUpdate();

xdmp.trace("tst-trigger", "PRE-COMMIT");
xdmp.trace("tst-trigger", uri);
xdmp.trace("tst-trigger", cts.doc(uri));
var props = [fn.head(xdmp.unquote('<priority>1</priority>')).root,
             fn.head(xdmp.unquote('<status>ingested</status>')).root];
xdmp.documentSetProperties(
       uri, props);
xdmp.documentSetMetadata(uri, {"status","ingested"});
