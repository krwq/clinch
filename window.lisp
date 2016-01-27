;;;; window.lisp
;;;; Please see the licence.txt for the CLinch 

(in-package #:clinch)

;;;; window.lisp

(defparameter *window* nil)
(defparameter *context* nil)

(defparameter *inited* nil)
(defparameter *running* nil)

(defparameter *controllers* nil)
(defparameter *haptic* nil)

(defparameter *next* nil
  "Runs before the next on-idle call. No arguments.")
(defparameter *on-window-size-changed* nil
  "Always called when window size changes. Arguments (window width height timestamp)")
(defparameter *on-window-resized* nil
  "Always called when window size changes. Arguments (window width height timestamp)")
(defparameter *on-window-hidden* nil
  "Called when window is hidden. Arguments (window timestamp)")
(defparameter *on-window-exposed* nil
  "Called when window is exposed and need redrawn. Arguments (window timestamp)")
(defparameter *on-window-moved* nil
  "Called when the window has been moved. Arguments (window x y timestamp)")
(defparameter *on-window-minimized* nil
  "Called when window is minimized. Arguments (window timestamp)")
(defparameter *on-window-maximized* nil
  "Called when window is maximized. Arguments (window timestamp)")
(defparameter *on-window-restored* nil
  "Called when window is restored to normal position and size. Arguments (window timestamp)")
(defparameter *on-window-enter* nil
  "Called when window gains mouse focus. Arguments (window timestamp)")
(defparameter *on-window-leave* nil
  "Called when window is loses mouse focus. Arguments (window timestamp)")
(defparameter *on-window-focus-gained* nil
  "Called when window gains focus. Arguments (window timestamp)")
(defparameter *on-window-focus-lost* nil
  "Called when window loses focus. Arguments (window timestamp)")
(defparameter *on-window-close* nil
  "Called when window is closing. Arguments (window timestamp)")

(defparameter *on-key-down* nil
  "Called when a key is pressed. Arguments (win keysym state ts)")
(defparameter *on-key-up* nil
  "Called when a key is released. Arguments (win keysym state ts)")

(defparameter *on-mouse-move* nil
  "Called when mouse is moved. Arguments (win mouse state x y xrel yrel ts)")
(defparameter *on-mouse-down* nil
"Called when mouse button is pressed. Arguments: (win mouse x y button state clicks ts)")
(defparameter *on-mouse-up* nil
"Called when mouse button is released. Arguments: (win mouse x y button state clicks ts)")
(defparameter *on-mouse-click* nil
  "Called when mouse button is released. Arguments: (win mouse x y button state clicks ts)") ;; This isn't correct. !!!
(defparameter *on-mouse-double-click* nil)
(defparameter *on-mouse-wheel-move* nil
  "Called when the mouse wheel is moved. Arguments: (win mouse x y ts)")

(defparameter *on-controller-button-down* nil)
(defparameter *on-controller-button-up* nil)
(defparameter *on-controller-added* nil)
(defparameter *on-controller-removed* nil)
(defparameter *on-controller-remapped* nil)
(defparameter *on-controller-axis-move* nil)

(defparameter *on-idle* nil
  "Called when there are no pending events. Take no arguments.")
(defparameter *on-quit* nil
  "Called when clinch is about to exit. Take no arguments.")

(defmacro with-main (&body body)
  "Enables REPL access via UPDATE-SWANK in the main loop using SDL2. Wrap this around
the sdl2:with-init code."
  ;;TODO: understand this. Without this wrapping the sdl:with-init the sdl thread
  ;; is an "Anonymous thread" (tested using sb-thread:*current-thread*), while applying
  ;; this makes *current-thread* the same as the one one when queried directly from the
  ;; REPL thread: #<SB-THREAD:THREAD "repl-thread" RUNNING {adress...}>
  `(sdl2:make-this-thread-main
    (lambda ()
      ;; does work on linux+sbcl without the following line:
      #+sbcl (sb-int:with-float-traps-masked (:invalid) ,@body)
      #-sbcl ,@body)))

(defmacro continuable (&body body)
  "Helper macro that we can use to allow us to continue from an
error. Remember to hit C in slime or pick the restart so errors don't kill the app."
  `(restart-case (progn ,@body) (continue () :report "Continue")))

(defun update-swank ()
  "Called from within the main loop, this keep the lisp repl
working while cepl runs"
  (continuable
    (let ((connection (or swank::*emacs-connection* (swank::default-connection))))
      (when connection
	(swank::handle-requests connection t)))))

(defmacro call-all (loc &rest args)
  `(continuable
     (and ,loc (funcall ,loc ,@args))))

(defun ensure-cepl-compatible-setup ()
  (unless (>= (gl:major-version) 3)
    (error "Cepl requires OpenGL 3.1 or higher. Found: ~a.~a"
           (gl:major-version) (gl:minor-version))))

(defun set-default-gl-options ()
  (print "Setting default options")
  (gl:clear-color 0.0 0.0 0.0 0.0)
  (gl:enable :cull-face)
  (gl:cull-face :back)
  (gl:front-face :ccw)
  (gl:enable :depth-test)
  (gl:depth-mask :true)
  (gl:depth-func :less)
  (gl:depth-range 0.0 1.0)
  (gl:enable :depth-clamp))


(defun init-controllers ()
  (setf *controllers* nil
	*haptic* nil)

  (format t "Opening game controllers. ~A ~%"
	  (sdl2-ffi.functions::sdl-game-controller-add-mappings-from-rw
	   (sdl2::sdl-rw-from-file  "gamecontrollerdb.txt" "rw") 1))
  (finish-output)
  ;; open any game controllers

  (loop for i from 0 upto (- (sdl2:joystick-count) 1)
     do (when (sdl2:game-controller-p i)
	  (format t "Found gamecontroller: ~a~%"
		  (sdl2:game-controller-name-for-index i))
	  
	  (let* ((gc (sdl2:game-controller-open i))
		 (joy (sdl2:game-controller-get-joystick gc)))
	    (setf *controllers* (acons i gc *controllers*))
	    (when (sdl2:joystick-is-haptic-p joy)
	      (let ((h (sdl2:haptic-open-from-joystick joy)))
		(setf *haptic* (acons i h *haptic*))
		(sdl2:rumble-init h))))))
  
  (format t "Controlers found: ~A~%" *controllers*))

(defun uninit-controllers ()
  (format t "Closing opened game controllers.~%")
  (finish-output)
  ;; close any game controllers that were opened
  ;; as well as any haptics
  (loop for (i . controller) in *controllers*
     do (progn
	  (format t "sdl2:haptic-close~%")
	  (sdl2:haptic-close (cdr (assoc i *haptic*)))
	  
	  (format t "sdl2:game-controller-close~%")
	  (sdl2:game-controller-close controller))))

(defun main-loop (win gl-context w h)
  ;;(declare (optimize (speed 3)))

  (call-all *next*)
  (setf *next* nil)
  (call-all *on-window-size-changed* win w h nil)
  (call-all *on-window-resized* win w h nil)

  (sdl2:with-event-loop (:method :poll)
    
    (:keydown
     (:window-id win :state state :keysym keysym :timestamp ts)
     (call-all *on-key-down* win keysym state ts))

    (:keyup
     (:window-id win :state state :keysym keysym :timestamp ts)
     (call-all *on-key-up* win keysym state ts))
    
    (:controlleraxismotion
     (:which controller-id :axis axis-id :value value :timestamp ts)
     (call-all *on-controller-axis-move* controller-id axis-id value ts))
    
    (:controllerbuttondown
     (:which controller-id :button button :timestamp ts)
     (call-all *on-controller-button-down* controller-id button ts))

    (:controllerbuttonup
     (:which controller-id :button button :timestamp ts)
     (call-all *on-controller-button-up* controller-id button ts))

    (:controlleradded 
     (:window-id win :data1 d1 :data2 d2 :timestamp ts)
     (call-all *on-controller-added* win d1 d2 ts))
    
    (:controllerremoved
     (:window-id win :data1 d1 :data2 d2 :timestamp ts)
     (call-all *on-controller-removed* win d1 d2 ts))

    (:controllerremapped
     (:window-id win :data1 d1 :data2 d2 :timestamp ts)
     (call-all *on-controller-remapped* win d1 d2 ts))
    
    (:mousemotion
     (:window-id win :which mouse :state state :x x :y y :xrel xrel :yrel yrel :timestamp ts)
     (declare (ignore x))
     (call-all *on-mouse-move* win mouse state x y xrel yrel ts))

    (:mousebuttondown
     (:window-id win :which mouse :x x :y y :button button :state state :clicks clicks :timestamp ts)
     (declare (ignore x))
     (call-all *on-mouse-down* win mouse x y button state clicks ts))

    (:mousebuttonup
     (:window-id win :which mouse :x x :y y :button button :state state :clicks clicks :timestamp ts)
     (declare (ignore x))
     (call-all *on-mouse-up* win mouse x y button state clicks ts))

    (:mouseclick
     (:window-id win :data1 d1 :data2 d2 :timestamp ts)
     (call-all *on-mouse-click* win d1 d2 ts)) ;;; FIX THIS!!!

    (:mousedoubleclick
     (:window-id win :data1 d1 :data2 d2 :timestamp ts)
     (call-all *on-mouse-double-click* win d1 d2 ts)) ;;; FIX THIS!!!

    (:mousewheel
     (:window-id win :which mouse :x x :y y :timestamp ts) 
     (declare (ignore x))
     (call-all *on-mouse-wheel-move* win mouse x y ts))
    
    (:windowevent
     (:event raw-event :window-id win :data1 d1 :data2 d2 :timestamp ts)
     (let ((event (autowrap:enum-key 'sdl2-ffi:sdl-window-event-id raw-event)))
       (cond
	 ((eql event :size-changed) (call-all *on-window-size-changed* win d1 d2 ts))
	 ((eql event :resized) (call-all *on-window-resized* win d1 d2 ts))
	 ((eql event :hidden) (call-all *on-window-hidden* win ts))
	 ((eql event :exposed) (call-all *on-window-exposed* win ts))
	 ((eql event :moved) (call-all *on-window-moved* win d1 d2 ts))
	 ((eql event :minimized) (call-all *on-window-minimized* win ts))
	 ((eql event :maximized) (call-all *on-window-maximized* win ts))
	 ((eql event :restored) (call-all *on-window-restored* win ts))
	 ((eql event :enter) (call-all *on-window-enter* win ts))
	 ((eql event :leave) (call-all *on-window-leave* win ts))
	 ((eql event :focus-gained) (call-all *on-window-focus-gained* win ts))
	 ((eql event :focus-lost) (call-all *on-window-focus-lost* win ts))
	 ((eql event :close) (call-all *on-window-close* win ts)
	  (print "Done...")
	  ))))
    
    (:idle ()  
	   (if *running*
	       (progn
		   (call-all *next*)
		   (setf *next* nil)
		   (call-all *on-idle*))
	       (sdl2:push-event :quit))
	   (gl:flush)
	   (sdl2:gl-swap-window win)
	   (update-swank))
    
    (:quit ()
	   (call-all *on-quit*)
	   t)))


(defun init (&optional
	       (width 800)
	       (height 600)
	       (title "Clank")
	       (fullscreen nil)
	       (no-frame nil)
	       (alpha-size 8)
	       (depth-size 32)
	       (stencil-size 32)
	       (red-size 8)
	       (green-size 8)
	       (blue-size 8)
	       (buffer-size 0)
	       (double-buffer t)
	       (hidden nil)
	       (resizable :resizable))

  (bordeaux-threads:make-thread (lambda ()
				  (_init width 
					 height 
					 title 
					 fullscreen
					 no-frame
					 alpha-size
					 depth-size 
					 stencil-size 
					 red-size 
					 green-size 
					 blue-size 
					 buffer-size
					 double-buffer
					 hidden 
					 resizable))
				:name "Main Clank Thread"
				:initial-bindings
				(cons (cons '*standard-output* *standard-output* )
				      (cons (cons '*standard-input* *standard-input*)
					    bordeaux-threads:*default-special-bindings*))))
	       

(defun _init (&optional
	       (width 800)
	       (height 600)
	       (title "Clank")
	       (fullscreen nil)
	       (no-frame nil)
	       (alpha-size 8)
	       (depth-size 32)
	       (stencil-size 32)
	       (red-size 8)
	       (green-size 8)
	       (blue-size 8)
	       (buffer-size 0)
	       (double-buffer t)
	       (hidden nil)
	       (resizable :resizable))

  (unless *running* 
    (let ((local-stdout *standard-output*)
	  (local-input *standard-input*))
      
      (with-main

	(unless *inited*
	  (sdl2:with-init (:everything)
	    
	    (let ((*standard-output* local-stdout)
		  (*standard-input* local-input))
	      
	      (setf *running* t)
	      
	      (format t "Using SDL Library Version: ~D.~D.~D~%"
		      sdl2-ffi:+sdl-major-version+
		      sdl2-ffi:+sdl-minor-version+
		      sdl2-ffi:+sdl-patchlevel+)
	      (finish-output)
	      ;;(init-controllers)

	      (sdl2:with-window (win :w width :h height ;;; :title title
				     :flags `(:shown :opengl :resizable
						     ,@(remove nil `(:shown :opengl
									   ,(when fullscreen :fullscreen-desktop)
									   ,(when resizable :resizable)
									   ,(when no-frame :borderless)
									   ,(when hidden :hidden)))))

		(sdl2:gl-set-attr :context-profile-mask 1)
		(sdl2:gl-set-attr :alpha-size alpha-size)
		(sdl2:gl-set-attr :depth-size depth-size)
		(sdl2:gl-set-attr :stencil-size stencil-size)
		(sdl2:gl-set-attr :red-size red-size)
		(sdl2:gl-set-attr :green-size green-size)
		(sdl2:gl-set-attr :blue-size blue-size)
		(sdl2:gl-set-attr :buffer-size buffer-size)
		(sdl2:gl-set-attr :doublebuffer (if double-buffer 1 0))

		(sdl2:with-gl-context (gl-context win)

		  (setf *window* win
			*context* gl-context)	
		  
		  (ensure-cepl-compatible-setup)
		  (set-default-gl-options)

		  ;; basic window/gl setup
		  (format t "Setting up window/gl.~%")
		  (finish-output)
		  (sdl2:gl-make-current win gl-context)
		  (gl:viewport 0 0 width height)
		  (gl:clear :color-buffer)
		  (format t "Beginning main loop.~%")
		  (finish-output)

		  (main-loop win gl-context width height)
		  (unload-all-uncollected)
		  (setf *running* nil
			*inited* nil))))))))))


(defun uninit ()
  (with-main
    (setf *running* nil
	  *inited* nil)

    (uninit-controllers) 
    (sdl2:push-event :quit)))

