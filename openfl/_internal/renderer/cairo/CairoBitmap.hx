package openfl._internal.renderer.cairo;


#if cpp
import cpp.Pointer;
#end
import lime.graphics.cairo.CairoFormat;
import lime.graphics.cairo.CairoPattern;
import lime.graphics.cairo.CairoSurface;
import openfl._internal.renderer.RenderSession;
import openfl.display.Bitmap;

@:access(lime.graphics.ImageBuffer)
@:access(openfl.display.Bitmap)
@:access(openfl.display.BitmapData)
@:access(openfl.geom.Matrix)


class CairoBitmap {
	
	
	public static inline function render (bitmap:Bitmap, renderSession:RenderSession):Void {
		
		if (!bitmap.__renderable || bitmap.__worldAlpha <= 0) return;
		
		//var context = renderSession.context;
		var cairo = renderSession.cairo;
		
		if (bitmap.bitmapData != null && bitmap.bitmapData.__isValid) {
			
			if (bitmap.__mask != null) {
				
				renderSession.maskManager.pushMask (bitmap.__mask);
				
			}
			
			//bitmap.bitmapData.__sync ();
			
			//context.globalAlpha = bitmap.__worldAlpha;
			var transform = bitmap.__worldTransform;
			var scrollRect = bitmap.scrollRect;
			
			if (renderSession.roundPixels) {
				
				var matrix = transform.__toMatrix3 ();
				matrix.tx = Math.round (matrix.tx);
				matrix.ty = Math.round (matrix.ty);
				cairo.matrix = matrix;
				//context.setTransform (transform.a, transform.b, transform.c, transform.d, Std.int (transform.tx), Std.int (transform.ty));
				
			} else {
				
				cairo.matrix = transform.__toMatrix3 ();
				//context.setTransform (transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty);
				
			}
			
			//if (!bitmap.smoothing) {
				//
				//untyped (context).mozImageSmoothingEnabled = false;
				//untyped (context).webkitImageSmoothingEnabled = false;
				//untyped (context).imageSmoothingEnabled = false;
				//
			//}
			
			var surface = bitmap.bitmapData.getSurface ();
			
			if (surface != null) {
				
				cairo.setSourceSurface (surface, 0, 0);
				
				if (scrollRect != null) {
					
					cairo.pushGroup ();
					cairo.setSourceSurface (surface, 0, 0);
					cairo.newPath ();
					cairo.rectangle (scrollRect.x, scrollRect.y, scrollRect.width, scrollRect.height);
					cairo.fill ();
					cairo.popGroupToSource ();
					
				}
				
				if (bitmap.__worldAlpha == 1) {
					
					cairo.paint ();
					
				} else {
					
					cairo.paintWithAlpha (bitmap.__worldAlpha);
					
				}
				
			}
			
			//if (!bitmap.smoothing) {
				//
				//untyped (context).mozImageSmoothingEnabled = true;
				//untyped (context).webkitImageSmoothingEnabled = true;
				//untyped (context).imageSmoothingEnabled = true;
				//
			//}
			
			if (bitmap.__mask != null) {
				
				renderSession.maskManager.popMask ();
				
			}
			
		}
		
	}
	
	
}