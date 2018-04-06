'use strict';
declareUpdate();

xdmp.trace("tst-trigger", "PRE-COMMIT");
xdmp.trace("tst-trigger", uri);
var doc = cts.doc(uri);
xdmp.trace("tst-trigger", doc);
var modifiableDoc = doc.toObject();
modifiableDoc.extra = "Hello";
var props = [fn.head(xdmp.unquote('<priority>1</priority>')).root,
             fn.head(xdmp.unquote('<status>ingested</status>')).root];
xdmp.documentSetProperties(uri, props);
xdmp.documentSetMetadata(uri, {"status":"ingested"});
xdmp.documentInsert(uri, modifiableDoc, 
		{metadata: xdmp.documentGetMetadata(uri),
        permissions : xdmp.documentGetPermissions(uri),
        collections : xdmp.documentGetCollections(uri)} )

