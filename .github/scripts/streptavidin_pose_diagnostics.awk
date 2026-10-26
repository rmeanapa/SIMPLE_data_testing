# GNU awk companion to streptavidin_pose_diagnostics.sh.
# Bash supplies case/map/worker inventories. main() writes CSVs, HTML and five SVGs.
# Arrays indexed by case (and iteration/particle) keep each measurement separate.
# Native pose rows retain their order; identity fields are checked before comparison.
# Missing supplemental evidence creates notices, while other measurements still render.

BEGIN {
	pi = atan2(0, -1)
	split("#0072b2 #009e73 #cc79a7 #d55e00 #222222", colors, " ")
	required["e1"]
	required["e2"]
	required["e3"]
	required["x"]
	required["y"]
	required["state"]
	identity["eo"]
	identity["stkind"]
	identity["indstk"]
	identity["pind"]
	for (s = 1; s <= 4; s++) {
		for (k = 1; k <= 3; k++) {
			sym[s, k] = (s == 1 || s == k + 1 ? 1 : -1)
		}
	}
	if (mode == "curve") {
		a = curve_status(curve, 0.5)
		b = curve_status(curve, 0.143)
		print a "\t" b "\t" endpoint
		exit 
	}
	if (root != "") {
		main()
	}
}


# D2 acts by right multiplication: four column-sign combinations.
function angle(a, b, s, j, k, tr, x, best)
{
	best = -1
	for (s = 1; s <= 4; s++) {
		tr = 0
		for (j = 1; j <= 9; j++) {
			k = (j - 1) % 3 + 1
			tr += a[j] * b[j] * sym[s, k]
		}
		x = (tr - 1) / 2
		if (x > best) {
			best = x
		}
	}
	if (best > 1) {
		best = 1
	}
	if (best < -1) {
		best = -1
	}
	return (atan2(sqrt(1 - best * best), best) * 180 / pi)
}

function cell(s)
{
	return ("<td>" value(s) "</td>")
}

function collect_case(c, dir, file, line, p, i, it, k, series, havecfar, parts, key, metric, counts, v, pair, exits, metrics, mode_cont)
{
	if (dir == "-") {
		note(c, "Missing or ambiguous case directory")
		return 
	}
	parse_log(c, dir "/LOG")
	file = dir "/reconstruct.log"
	while ((getline line < file) > 0) {
		if (match(line, /Execution time:[[:space:]]*[-+0-9.EeDd]+/)) {
			v = substr(line, RSTART, RLENGTH)
			sub(/^.*:[[:space:]]*/, "", v)
			reconstruct[c] = number(v)
		}
	}
	close(file)
	if (! niter[c]) {
		note(c, "Iteration records unavailable")
	}
	file = dir "/STEP_TIMING.tsv"
	while ((getline line < file) > 0) {
		split(line, p, "\t")
		if (p[1] == "refine") {
			runtime[c] = p[4]
			refine_exit[c] = p[5]
		}
		if (p[1] == "reconstruct") {
			reconstruct[c] = p[4]
			reconstruct_exit[c] = p[5]
		}
	}
	close(file)
	pose_metrics(c, dir "/initial/poses.txt", dir "/final_poses.txt")
	for (i = 1; i <= niter[c]; i++) {
		it = iteration[c, i]
		series = 2 * case_index[c] - 1
		label["half", series] = c " FSC=0.5"
		label["half", series + 1] = c " FSC=0.143"
		dashed["half", series + 1] = 1
		label["cfar", case_index[c]] = c
		if ((c, it) in half05) {
			point("half", series, it, half05[c, it])
		}
		if ((c, it) in half143) {
			point("half", series + 1, it, half143[c, it])
		}
		if ((c, it) in cfar) {
			point("cfar", case_index[c], it, cfar[c, it])
			havecfar = 1
		}
		print(quote(c) "," it "," half05[c, it] "," half143[c, it] "," cfar[c, it] "," iter_converged[c, it]) >> (out "/internal_iterations.csv")
	}
	if (! havecfar) {
		note(c, "cFAR unavailable: no logged values")
	}
	file = out "/worker_files.tsv"
	while ((getline line < file) > 0) {
		split(line, p, "\t")
		if (p[1] != c) {
			continue
		}
		if (p[2] == "exit") {
			if ((getline v < p[3]) > 0) {
				print(quote(c) "," quote(p[3]) "," quote(v)) >> (out "/worker_exits.csv")
				exits++
			}
			close(p[3])
		} else {
			parts++
			while ((getline v < p[3]) > 0) {
				if (v ~ /\*\*\* BENCHMARK RECORD \*\*\*/) {
					mode_cont = 0
				}
				if (v ~ /match3D refine mode[[:space:]]*:/) {
					sub(/^.*:[[:space:]]*/, "", v)
					mode_cont = (v == "cont")
				}
				if (mode_cont && v ~ /^[[:space:]]*match3D cont /) {
					split(v, pair, ":")
					gsub(/^[[:space:]]+|[[:space:]]+$/, "", pair[1])
					gsub(/[[:space:]]/, "", pair[2])
					if (pair[2] ~ /^[0-9]+$/) {
						counts[pair[1]] += pair[2]
					}
				}
			}
			close(p[3])
		}
	}
	close(file)
	for (key in counts) {
		print(quote(c) "," quote(key) "," counts[key] "," parts) >> (out "/optimizer_counts.csv")
		metrics++
	}
	if (! metrics) {
		note(c, "Optimizer counters unavailable: no retained continuous benchmark records")
	}
	if (! exits) {
		note(c, "Worker exit codes unavailable: no retained terminal records")
	}
	if (error[c]) {
		stop[c] = "execution error"
	} else if (converged[c] == "yes") {
		stop[c] = "converged"
	} else if (normal[c] && actual[c] == budget[c]) {
		stop[c] = "iteration budget"
	} else {
		stop[c] = "not recorded"
	}
}

function crossing(v, state, endpoint)
{
	if (state == "crossed") {
		return v
	}
	if (state == "above_threshold_through_endpoint") {
		return ("Above threshold through " endpoint " A endpoint; no measured crossing")
	}
	return "Unavailable: no downward crossing within sampled range"
}

# A measured threshold crossing requires a downward bracket between adjacent samples.
function curve_status(file, t, line, p, prior, have, above, below, crossed, n)
{
	above = 1
	below = 1
	endpoint = ""
	n = 0
	while ((getline line < file) > 0) {
		split(line, p, ",")
		if (p[1] == "resolution_angstrom") {
			continue
		}
		if (! numeric(p[1]) || ! numeric(p[2])) {
			close(file)
			return "invalid_samples"
		}
		if (have && prior > t && number(p[2]) <= t) {
			crossed = 1
		}
		prior = number(p[2])
		have = 1
		n++
		if (prior <= t) {
			above = 0
		}
		if (prior > t) {
			below = 0
		}
		if (endpoint == "" || number(p[1]) < endpoint) {
			endpoint = number(p[1])
		}
	}
	close(file)
	if (! n) {
		return "unavailable"
	}
	if (crossed) {
		return "crossed"
	}
	return (above ? "above_threshold_through_endpoint" : "no_downward_crossing_in_sampled_range")
}

# Plot at most about 500 quantiles per series; CSVs retain every compared particle.
function distribution(c, data, n, kind, phase, tmp, i, series)
{
	for (i = 1; i <= n; i++) {
		tmp[i] = data[c, i]
	}
	asort(tmp)
	series = 2 * case_index[c] - 2 + phase
	label[kind, series] = c " " (phase == 1 ? "initial" : "final")
	dashed[kind, series] = (phase == 1)
	for (i = 1; i <= n; i++) {
		if (i == 1 || i == n || i % int(n / 500 + 1) == 0) {
			point(kind, series, 100 * i / n, tmp[i])
		}
	}
}

function draw_plot(kind, file, title, ytitle, xtitle, s, i, n, x, y, xmin, xmax, ymin, ymax, pad, X, Y, points, colour, height)
{
	n = 0
	for (s = 1; s <= 10; s++) {
		for (i = 1; i <= np[kind, s]; i++) {
			x = px[kind, s, i]
			y = py[kind, s, i]
			if (! n || x < xmin) {
				xmin = x
			}
			if (! n || x > xmax) {
				xmax = x
			}
			if (! n || y < ymin) {
				ymin = y
			}
			if (! n || y > ymax) {
				ymax = y
			}
			n++
		}
	}
	height = 660
	print("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 880 " height "\"><rect width=\"100%\" height=\"100%\" fill=\"white\"/><g font-family=\"sans-serif\" font-size=\"13\" fill=\"#222\">") > file
	print("<text x=\"75\" y=\"28\" font-size=\"18\">" esc(title) "</text>") >> file
	if (! n) {
		print("<text x=\"75\" y=\"85\">Diagnostic unavailable: no valid records</text></g></svg>") >> file
		close(file)
		return 
	}
	if (xmax == xmin) {
		xmax = xmin + 1
	}
	pad = (ymax - ymin) * 0.08
	if (pad < 0.01) {
		pad = 0.01
	}
	ymin -= pad
	if (ymin < 0) {
		ymin = 0
	}
	ymax += pad
	print("<text x=\"18\" y=\"52\">" esc(ytitle) "</text><text x=\"250\" y=\"385\">" esc(xtitle) "</text>") >> file
	for (i = 0; i <= 5; i++) {
		y = ymin + (ymax - ymin) * i / 5
		Y = 340 - 270 * i / 5
		printf("<path d=\"M75 %.2f H765\" stroke=\"#ddd\"/><text x=\"65\" y=\"%.2f\" text-anchor=\"end\">%.3g</text>\n", Y, Y + 4, y) >> file
	}
	for (s = 1; s <= 10; s++) {
		if (! np[kind, s]) {
			continue
		}
		points = ""
		colour = colors[kind == "cfar" ? s : int((s + 1) / 2)]
		for (i = 1; i <= np[kind, s]; i++) {
			X = 75 + 690 * (px[kind, s, i] - xmin) / (xmax - xmin)
			Y = 340 - 270 * (py[kind, s, i] - ymin) / (ymax - ymin)
			points = points sprintf("%.2f,%.2f ", X, Y)
		}
		print("<polyline points=\"" points "\" fill=\"none\" stroke=\"" colour "\" stroke-width=\"2\" " (dashed[kind, s] ? "stroke-dasharray=\"7 4\"" : "") "/>") >> file
		print("<text x=\"75\" y=\"" (410 + 22 * s) "\" fill=\"" colour "\">" esc(label[kind, s]) "</text>") >> file
	}
	printf("<text x=\"75\" y=\"362\">%g</text><text x=\"745\" y=\"362\">%g</text></g></svg>\n", xmin, xmax) >> file
	close(file)
}

# GNU awk diagnostics: native pose tables/logs in, CSVs and SVGs out.
# Entry points: main() for a report; curve_status() for native FSC samples.
function esc(s)
{
	gsub(/&/, "\\&amp;", s)
	gsub(/</, "\\&lt;", s)
	gsub(/>/, "\\&gt;", s)
	gsub(/\"/, "\\&quot;", s)
	return s
}

function identity_row(title, s)
{
	print("<tr><th>" title "</th>" cell(s) "</tr>") >> html
}

function main(file, line, p, i, j, c, dir, k, sha, commitlist, name, svg, figs, titles, kind)
{
	html = out "/fragment.html"
	print("case,diagnostic") > (out "/diagnostic_notices.csv")
	print("case,iterations,requested_maxits,effective_maxits,first_convergence_iteration,converged,stop_reason,refine_seconds,reconstruct_seconds,refine_exit_code,reconstruct_exit_code") > (out "/summary.csv")
	print("case,iteration,half_fsc05,half_fsc0143,cfar,converged") > (out "/internal_iterations.csv")
	print("case,particle_row,initial_angle_deg,final_angle_deg,initial_shift_px,final_shift_px") > (out "/pose_disagreements.csv")
	print("case,initially_active,compared_particles,initial_angle_median_deg,final_angle_median_deg,initial_angle_p90_deg,final_angle_p90_deg,final_angle_max_deg,angle_improved_percent") > (out "/pose_summary.csv")
	print("case,metric,count,benchmark_parts") > (out "/optimizer_counts.csv")
	print("case,file,exit_code") > (out "/worker_exits.csv")
	print("case,iteration,map_type,volume,direct_cc,mirrored_cc,hand,reference_fsc05,reference_fsc0143,crossing_05,crossing_0143,endpoint_A") > (out "/reference_iterations.csv")
	read_properties(root "/RUN_METADATA.tsv", meta)
	read_properties(root "/inputs.tsv", inputs)
	if (inputs["requested_maxits"] == "") {
		inputs["requested_maxits"] = "automatic"
	}
	original_ok = read_poses(root "/preparation/original_poses.txt", "o")
	file = out "/case_index.tsv"
	while ((getline line < file) > 0) {
		split(line, p, "\t")
		c = p[1]
		cases[++ncases] = c
		case_index[c] = ncases
		dirs[c] = p[2]
		collect_case(c, p[2])
		print(quote(c) "," actual[c] "," quote(inputs["requested_maxits"]) "," budget[c] "," first[c] "," quote(converged[c]) "," quote(stop[c]) "," runtime[c] "," reconstruct[c] "," refine_exit[c] "," reconstruct_exit[c]) >> (out "/summary.csv")
		for (k in poses) {
			split(k, p, SUBSEP)
			if (p[1] == c "i" || p[1] == c "f") {
				delete poses[k]
			}
		}
	}
	close(file)
	file = out "/collector_notices.tsv"
	while ((getline line < file) > 0) {
		split(line, p, "\t")
		note(p[1], p[2])
	}
	close(file)
	file = root "/INPUT_SHA256SUMS"
	while ((getline line < file) > 0) {
		split(line, p, /[[:space:]]+/)
		if (p[2] == inputs["executable"]) {
			sha = p[1]
		}
	}
	close(file)
	for (k in commits) {
		commitlist = commitlist (commitlist ? ", " : "") k
	}
	print("<section><h2>Run identity and timing</h2><table>") > html
	identity_row("Testing repository commit", meta["testing_commit"])
	identity_row("Testing scripts modified at launch", meta["testing_dirty"])
	identity_row("SIMPLE commit from execution logs", commitlist)
	identity_row("SIMPLE executable SHA-256", sha)
	identity_row("Benchmark started UTC", meta["started_utc"])
	identity_row("Benchmark finished UTC", meta["finished_utc"])
	identity_row("Total benchmark seconds", meta["elapsed_seconds"])
	identity_row("Status", meta["status"])
	identity_row("Exit code", meta["exit_code"])
	identity_row("Report generated UTC", reporttime)
	print("</table>") >> html
	if (meta["github_repository"] ~ /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/ && meta["github_run_id"] ~ /^[0-9]+$/) {
		print("<p><a href=\"https://github.com/" meta["github_repository"] "/actions/runs/" meta["github_run_id"] "\">GitHub Action run " meta["github_run_id"] "</a></p>") >> html
	}
	print("<h3>Refinement</h3><div style=\"overflow-x:auto\"><table><tr><th>Case</th><th>Iterations</th><th>Requested budget</th><th>Effective budget</th><th>First convergence</th><th>Final convergence</th><th>Stop reason</th><th>Reconstruct seconds</th><th>Refine seconds</th></tr>") >> html
	for (i = 1; i <= ncases; i++) {
		c = cases[i]
		print("<tr>" cell(c) cell(actual[c]) cell(inputs["requested_maxits"]) cell(budget[c]) cell(first[c] == "" ? "Not detected" : first[c]) cell(converged[c]) cell(stop[c]) cell(reconstruct[c]) cell(runtime[c]) "</tr>") >> html
	}
	print("</table></div><p>First convergence means the first positive criterion detection, even when minimum iterations require further refinement. Reconstruction and refinement wall times are separate. Convergence describes stability and does not establish pose recovery.</p>") >> html
	print("<h3>Initial and final raw-map reference agreement</h3><div style=\"overflow-x:auto\"><table><tr><th>Case</th><th>Map</th><th>Direct CC</th><th>Mirrored CC</th><th>Hand</th><th>FSC 0.5 (A)</th><th>FSC 0.143 (A)</th></tr>") >> html
	reference_rows()
	print("</table></div><p>Reference trends use retained low-pass iteration maps. Both thresholds share one Y-axis. Sampling endpoints without a crossing are excluded from plotted crossing values and identified in the CSV.</p>") >> html
	for (i = 1; i <= ncases; i++) {
		c = cases[i]
		for (j = 1; j <= niter[c]; j++) {
			if (! ref_seen[c, iteration[c, j]]) {
				note(c, "Reference FSC trend incomplete: retained maps do not cover all iterations")
				break
			}
		}
	}
	print("<h3>Particle pose recovery</h3><p>Agreement with original estimated poses, modulo D2 symmetry; these are not independent pose truth. No global frame or origin correction is fitted. Statistics use particles active initially and finally. P90 uses the nearest-rank definition.</p><div style=\"overflow-x:auto\"><table><tr><th>Case</th><th>Compared / initially active</th><th>Initial median (deg)</th><th>Final median (deg)</th><th>Initial P90 (deg)</th><th>Final P90 (deg)</th><th>Worst final (deg)</th><th>Improved (%)</th></tr>") >> html
	for (i = 1; i <= ncases; i++) {
		c = cases[i]
		print("<tr>" cell(c) cell(value(compared[c]) " / " value(initially_active[c])) cell(med[c, "initial"]) cell(med[c, "final"]) cell(pctl[c, "initial"]) cell(pctl[c, "final"]) cell(worst[c]) cell(recovery[c]) "</tr>") >> html
	}
	print("</table></div>") >> html
	if (nnotice) {
		print("<h3>Unavailable supplemental diagnostics</h3><ul>") >> html
		for (i = 1; i <= nnotice; i++) {
			print("<li>" esc(notices[i]) "</li>") >> html
		}
		print("</ul>") >> html
	}
	prefix = "../comparisons/streptavidin_pose_errors/diagnostics/"
	split("summary internal_iterations reference_iterations pose_disagreements pose_summary optimizer_counts worker_exits diagnostic_notices", p, " ")
	print("<p>Supporting CSVs: ") >> html
	for (i = 1; i <= 8; i++) {
		print("<a href=\"" prefix p[i] ".csv\">" p[i] "</a> ") >> html
	}
	print("</p><p>Optimizer counters sum retained continuous-search records; worker exits are retained terminal records. Missing records are not assumed to be zero.</p>") >> html
	draw_plot("half", out "/internal_fsc.svg", "Internal half-map FSC", "Resolution (A)", "Iteration")
	draw_plot("cfar", out "/cfar.svg", "Internal cFAR", "cFAR", "Iteration")
	draw_plot("reference", out "/reference_fsc.svg", "Reference FSC of retained low-pass maps", "Resolution (A)", "Iteration")
	draw_plot("angles", out "/pose_angle_deg.svg", "Angular agreement with original estimates", "D2 angular disagreement (degrees)", "Particle percentile")
	draw_plot("shifts", out "/pose_shift_px.svg", "Shift agreement with original estimates", "Shift disagreement (pixels)", "Particle percentile")
	print("<style>.pose-figures{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px}.pose-figures svg{width:100%;height:auto}@media(max-width:800px){.pose-figures{grid-template-columns:1fr}}</style><div class=\"pose-figures\">") >> html
	split("internal_fsc cfar reference_fsc pose_angle_deg pose_shift_px", figs, " ")
	for (i = 1; i <= 5; i++) {
		name = figs[i] ".svg"
		print("<a href=\"" prefix name "\" title=\"Open full size\">") >> html
		file = out "/" name
		while ((getline line < file) > 0) {
			print(line) >> html
		}
		close(file)
		print("</a>") >> html
	}
	print("</div></section>") >> html
	close(html)
	print((nnotice ? "partial" : "complete")) > (out "/status.txt")
}

function note(c, s)
{
	notices[++nnotice] = c ": " s
	print(quote(c) "," quote(s)) >> (out "/diagnostic_notices.csv")
}

function number(s)
{
	gsub(/[Dd]/, "e", s)
	return (s + 0)
}

function numeric(s)
{
	return (s ~ /^[-+]?([0-9]+([.][0-9]*)?|[.][0-9]+)([EeDd][-+]?[0-9]+)?$/)
}

# Close an iteration at its final convergence flag, before final reconstruction metrics.
function parse_log(c, file, line, p, it, live, v, flag)
{
	while ((getline line < file) > 0) {
		if (line ~ />>> ITERATION[[:space:]]+[0-9]+[[:space:]]*$/) {
			split(line, p, /[[:space:]]+/)
			it = p[length(p)] + 0
			live = 1
			if (! iter_seen[c, it]++) {
				iteration[c, ++niter[c]] = it
			}
			actual[c] = it
		}
		if (match(line, /MAXITS( COMMAND-LINE OVERRIDE)?:[[:space:]]*[0-9]+/)) {
			v = substr(line, RSTART, RLENGTH)
			sub(/^.*:[[:space:]]*/, "", v)
			budget[c] = v
		}
		if (match(line, /Execution time:[[:space:]]*[-+0-9.EeDd]+/)) {
			v = substr(line, RSTART, RLENGTH)
			sub(/^.*:[[:space:]]*/, "", v)
			runtime[c] = number(v)
		}
		if (match(line, /SIMPLE Git Commit:[[:space:]]*[0-9a-fA-F]+/)) {
			v = substr(line, RSTART, RLENGTH)
			sub(/^.*:[[:space:]]*/, "", v)
			commits[v] = 1
		}
		if (line ~ /ERROR!|ERROR STOP/) {
			error[c] = 1
		}
		if (line ~ /SIMPLE_REFINE3D NORMAL STOP/) {
			normal[c] = 1
		}
		if (! live) {
			continue
		}
		if (line ~ /RESOLUTION @ FSC=0[.]143[[:space:]]+AVG\/SDEV\/MIN\/MAX:/) {
			v = line
			sub(/^.*MAX:[[:space:]]*/, "", v)
			split(v, p, " ")
			half143[c, it] = number(p[1])
		}
		if (line ~ /RESOLUTION @ FSC=0[.]5[[:space:]]+AVG\/SDEV\/MIN\/MAX:/) {
			v = line
			sub(/^.*MAX:[[:space:]]*/, "", v)
			split(v, p, " ")
			half05[c, it] = number(p[1])
		}
		if (line ~ /\(cFAR\) STATE[[:space:]]+1:/) {
			v = line
			sub(/^.*1:[[:space:]]*/, "", v)
			split(v, p, " ")
			cfar[c, it] = number(p[1])
		}
		if (line ~ /CONVERGED: (yes|no)/) {
			flag = (line ~ /CONVERGED: yes/ ? "yes" : "no")
			if (flag == "yes" && first[c] == "") {
				first[c] = it
			}
			if (line ~ /continuing until minimum iteration count/) {
				continue
			}
			converged[c] = flag
			iter_converged[c, it] = flag
			live = 0
		}
	}
	close(file)
}

function point(kind, series, x, y, n)
{
	n = ++np[kind, series]
	px[kind, series, n] = x
	py[kind, series, n] = y
}

function pose_metrics(c, initial, final, n, i, k, active, d, a, b, ri, rf, oi, median, p90, improved)
{
	if (! original_ok || ! read_poses(initial, c "i") || ! read_poses(final, c "f")) {
		note(c, "Pose recovery unavailable: original, initial, or final native poses are missing/invalid")
		return 
	}
	n = pose_count["o"]
	if (pose_count[c "i"] != n || pose_count[c "f"] != n) {
		note(c, "Pose recovery unavailable: particle counts differ")
		return 
	}
	for (i = 1; i <= n; i++) {
		for (k in identity) {
			if (("o", i, k) in poses && (poses["o", i, k] != poses[c "i", i, k] || poses["o", i, k] != poses[c "f", i, k])) {
				note(c, "Pose recovery unavailable: particle identity/half assignment differs at row " i)
				return 
			}
		}
	}
	for (i = 1; i <= n; i++) {
		if (poses["o", i, "state"] <= 0 || poses[c "i", i, "state"] <= 0) {
			continue
		}
		initially_active[c]++
		if (poses[c "f", i, "state"] <= 0) {
			continue
		}
		active++
		rotation(poses["o", i, "e1"], poses["o", i, "e2"], poses["o", i, "e3"], oi)
		rotation(poses[c "i", i, "e1"], poses[c "i", i, "e2"], poses[c "i", i, "e3"], ri)
		rotation(poses[c "f", i, "e1"], poses[c "f", i, "e2"], poses[c "f", i, "e3"], rf)
		a = angle(oi, ri)
		b = angle(oi, rf)
		ai[c, active] = a
		af[c, active] = b
		if (b < a) {
			improved++
		}
		d = (poses[c "i", i, "x"] - poses["o", i, "x"]) ^ 2 + (poses[c "i", i, "y"] - poses["o", i, "y"]) ^ 2
		si[c, active] = sqrt(d)
		d = (poses[c "f", i, "x"] - poses["o", i, "x"]) ^ 2 + (poses[c "f", i, "y"] - poses["o", i, "y"]) ^ 2
		sf[c, active] = sqrt(d)
		print(quote(c) "," i "," a "," b "," si[c, active] "," sf[c, active]) >> (out "/pose_disagreements.csv")
	}
	compared[c] = active
	if (! active) {
		note(c, "Pose recovery unavailable: no particles active initially and finally")
		return 
	}
	stats(c, "initial", ai, active)
	stats(c, "final", af, active)
	recovery[c] = 100 * improved / active
	print(quote(c) "," initially_active[c] "," active "," med[c, "initial"] "," med[c, "final"] "," pctl[c, "initial"] "," pctl[c, "final"] "," worst[c] "," recovery[c]) >> (out "/pose_summary.csv")
	distribution(c, ai, active, "angles", 1)
	distribution(c, af, active, "angles", 2)
	distribution(c, si, active, "shifts", 1)
	distribution(c, sf, active, "shifts", 2)
}

function quote(s)
{
	gsub(/\"/, "\"\"", s)
	return ("\"" s "\"")
}

function read_poses(file, phase, line, p, i, n, k, v)
{
	n = 0
	while ((getline line < file) > 0) {
		n++
		split(line, p, /[[:space:]]+/)
		for (i in p) {
			if (! index(p[i], "=")) {
				continue
			}
			split(p[i], v, "=")
			if (! numeric(v[2]) || ! ((v[1] in required) || (v[1] in identity))) {
				continue
			}
			poses[phase, n, v[1]] = number(v[2])
		}
		for (k in required) {
			if (! ((phase, n, k) in poses)) {
				close(file)
				return 0
			}
		}
	}
	close(file)
	pose_count[phase] = n
	return (n > 0)
}

function read_properties(file, a, line, p)
{
	while ((getline line < file) > 0) {
		split(line, p, "\t")
		a[p[1]] = p[2]
	}
	close(file)
}

function reference_rows(file, line, p, c, it, kind, s, j)
{
	file = out "/references.tsv"
	while ((getline line < file) > 0) {
		split(line, p, "\t")
		c = p[1]
		it = p[2]
		kind = p[3]
		for (j = 1; j <= 12; j++) {
			printf("%s%s", quote(p[j]), (j == 12 ? "\n" : ",")) >> (out "/reference_iterations.csv")
		}
		if (kind == "iteration_lp") {
			ref_seen[c, it] = 1
			s = 2 * case_index[c] - 1
			label["reference", s] = c " FSC=0.5"
			label["reference", s + 1] = c " FSC=0.143"
			dashed["reference", s + 1] = 1
			if (p[10] == "crossed") {
				point("reference", s, it, p[8] + 0)
			}
			if (p[11] == "crossed") {
				point("reference", s + 1, it, p[9] + 0)
			}
		} else {
			print("<tr>" cell(c) cell(kind) cell(p[5]) cell(p[6]) cell(p[7]) cell(crossing(p[8], p[10], p[12])) cell(crossing(p[9], p[11], p[12])) "</tr>") >> html
		}
		if (p[10] != "crossed" || p[11] != "crossed") {
			note(c, kind " iteration " it ": FSC threshold not crossed within sampled range; see reference CSV")
		}
	}
	close(file)
}

# SIMPLE passive Z-Y-Z projection matrix, Rz(e3) Ry(e2) Rz(e1).
# SIMPLE passive Z-Y-Z matrix: Rz(e3) Ry(e2) Rz(e1).
function rotation(e1, e2, e3, r, a, b, c, ca, sa, cb, sb, cc, sc)
{
	a = e1 * pi / 180
	b = e2 * pi / 180
	c = e3 * pi / 180
	ca = cos(a)
	sa = sin(a)
	cb = cos(b)
	sb = sin(b)
	cc = cos(c)
	sc = sin(c)
	r[1] = cc * cb * ca - sc * sa
	r[2] = cc * cb * sa + sc * ca
	r[3] = -cc * sb
	r[4] = -sc * cb * ca - cc * sa
	r[5] = -sc * cb * sa + cc * ca
	r[6] = sc * sb
	r[7] = sb * ca
	r[8] = sb * sa
	r[9] = cb
}

function stats(c, phase, data, n, tmp, i)
{
	for (i = 1; i <= n; i++) {
		tmp[i] = data[c, i]
	}
	asort(tmp)
	med[c, phase] = (tmp[int((n + 1) / 2)] + tmp[int((n + 2) / 2)]) / 2
	pctl[c, phase] = tmp[int((9 * n + 9) / 10)]
	if (phase == "final") {
		worst[c] = tmp[n]
	}
}

function value(s)
{
	return (s == "" ? "Unavailable" : esc(s))
}
