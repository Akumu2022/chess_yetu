<!--
	SVG filters for the wood and marble boards. They draw their pattern as a translucent overlay on top of the
	flat square colours, so every colour scheme can be wood or marble. Mounted once in the layout; the board and the
	settings swatches refer to them by id (see textures.ts). Frequencies are per board square.
-->
<svg width="0" height="0" style="position: absolute" aria-hidden="true" focusable="false">
	<defs>
		<!-- long horizontal grain with a few darker growth rings -->
		<filter id="tex-wood" x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB">
			<feTurbulence type="fractalNoise" baseFrequency="0.07 2.1" numOctaves="3" seed="4" />
			<feColorMatrix
				type="matrix"
				values="0 0 0 0 0.16  0 0 0 0 0.08  0 0 0 0 0.02  1.9 0 0 0 -0.62"
			/>
		</filter>
		<!-- soft cloudy lightness -->
		<filter id="tex-cloud" x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB">
			<feTurbulence type="fractalNoise" baseFrequency="0.22 0.22" numOctaves="3" seed="11" />
			<feColorMatrix type="matrix" values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  1.6 0 0 0 -0.55" />
		</filter>
		<!-- thin dark veins where the turbulence is close to zero -->
		<filter id="tex-marble" x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB">
			<feTurbulence type="turbulence" baseFrequency="0.13 0.17" numOctaves="4" seed="9" />
			<feColorMatrix type="matrix" values="0 0 0 0 0.22  0 0 0 0 0.22  0 0 0 0 0.26  -7.5 0 0 0 1.55" />
		</filter>
	</defs>
</svg>
