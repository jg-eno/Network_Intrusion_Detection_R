let appData = null;
let charts = {}; // Store chart instances for safe destruction

document.addEventListener('DOMContentLoaded', () => {
    fetchData();
});

async function fetchData() {
    try {
        const dataResponse = await fetch('data.json');
        
        if (!dataResponse.ok) {
            throw new Error(`HTTP error! status: ${dataResponse.status}`);
        }
        
        appData = await dataResponse.json();
        
        // Render Global dataset stats
        if (appData.class_distribution) renderDistributionChart(appData.class_distribution);
        if (appData.top_features) renderEDAChart(appData.top_features);
        
        // Process Models
        if (appData.models && appData.models.length > 0) {
            renderTabs(appData.models);
            renderModelData(0); // Load first model by default
        } else {
            // Fallback for old data.json structure
            document.getElementById('model-tabs').innerHTML = '<p class="text-muted">No models array found. Using legacy format.</p>';
            renderLegacyDashboard(appData);
        }

    } catch (error) {
        console.error("Could not load data:", error);
        document.getElementById('metrics-container').innerHTML = 
            `<div class="metric-card loading-card"><p class="danger">Error loading data. Run the R pipeline first to generate data.json.</p></div>`;
    }
}

function renderTabs(models) {
    const container = document.getElementById('model-tabs');
    container.innerHTML = '';
    
    models.forEach((model, index) => {
        const btn = document.createElement('button');
        btn.className = `tab-btn ${index === 0 ? 'active' : ''}`;
        btn.textContent = model.name || `Model ${index + 1}`;
        btn.onclick = () => {
            document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            renderModelData(index);
        };
        container.appendChild(btn);
    });
}

function renderModelData(index) {
    const modelData = appData.models[index];
    
    // Trigger animation
    const section = document.querySelector('.model-metrics-section');
    section.classList.remove('fadeIn');
    void section.offsetWidth; // force reflow
    section.classList.add('fadeIn');

    // Render Metrics
    if (modelData.core_metrics) {
        renderMetrics(modelData.core_metrics);
    } else if (modelData.metrics) { 
        renderMetrics(modelData.metrics);
    }
    
    renderConfusionMatrix(modelData.cm_table);
    renderClassStats(modelData.class_metrics);
    
    if (modelData.roc_data && Array.isArray(modelData.roc_data) && modelData.roc_data.length > 0) {
        renderROCChart(modelData.roc_data);
    } else {
        // Clear canvas if no ROC data
        if (charts['rocChart']) charts['rocChart'].destroy();
        const canvas = document.getElementById('rocChart');
        if (canvas) canvas.getContext('2d').clearRect(0, 0, canvas.width, canvas.height);
    }
}

function renderLegacyDashboard(data) {
    if (data.core_metrics) renderMetrics(data.core_metrics);
    else if (data.metrics) renderMetrics(data.metrics);
    
    renderConfusionMatrix(data.cm_table);
    renderClassStats(data.class_metrics);
    if (data.roc_data) renderROCChart(data.roc_data);
}

function renderMetrics(metrics) {
    const container = document.getElementById('metrics-container');
    container.innerHTML = '';
    
    const icons = {
        Accuracy: `<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#2563eb" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"></circle><circle cx="12" cy="12" r="6"></circle><circle cx="12" cy="12" r="2"></circle></svg>`,
        Precision: `<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#6366f1" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"></circle><line x1="12" y1="8" x2="12" y2="16"></line><line x1="8" y1="12" x2="16" y2="12"></line></svg>`,
        Recall: `<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#8b5cf6" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"></path><polyline points="22 4 12 14.01 9 11.01"></polyline></svg>`,
        F1_Score: `<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#d946ef" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2v20"></path><path d="M17 5H9.5a3.5 3.5 0 0 0 0 7h5a3.5 3.5 0 0 1 0 7H6"></path></svg>`,
        AUC: `<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#10b981" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="22 7 13.5 15.5 8.5 10.5 2 17"></polyline><polyline points="16 7 22 7 22 13"></polyline></svg>`
    };

    const metricsToDisplay = [
        { key: 'Accuracy', label: 'Overall Accuracy', getBadge: v => v >= 0.95 ? 'Exceptional' : 'Standard', format: v => (v * 100).toFixed(2) + '%' },
        { key: 'Precision', label: 'Precision', getBadge: v => v >= 0.9 ? 'High Exactness' : 'Standard', format: v => (v * 100).toFixed(2) + '%' },
        { key: 'Recall', label: 'Recall (Sensitivity)', getBadge: v => v >= 0.9 ? 'High Detection' : 'Standard', format: v => (v * 100).toFixed(2) + '%' },
        { key: 'F1_Score', label: 'F1 Harmonic Score', getBadge: v => v >= 0.9 ? 'Optimum Balance' : 'Standard', format: v => (v * 100).toFixed(2) + '%' },
        { key: 'AUC', label: 'ROC-AUC', getBadge: v => v >= 0.9 ? 'Outstanding' : 'Acceptable', format: v => v.toFixed(4) }
    ];

    metricsToDisplay.forEach(item => {
        let val = metrics[item.key];
        if (Array.isArray(val)) val = val[0]; // R can return single-element arrays

        if (val !== null && val !== undefined && !isNaN(val)) {
            const card = document.createElement('div');
            card.className = 'metric-card';
            
            let badgeClass = 'badge-success';
            if (val < 0.9) badgeClass = 'badge-warning';

            card.innerHTML = `
                <div class="metric-label">${item.label} <span class="metric-icon">${icons[item.key] || ''}</span></div>
                <div class="metric-value">${item.format(val)}</div>
                <div><span class="badge ${badgeClass}">${item.getBadge(val)}</span></div>
            `;
            container.appendChild(card);
        }
    });
}

function renderDistributionChart(distData) {
    if (charts['distributionChart']) charts['distributionChart'].destroy();

    const labels = distData.map(d => `Class ${d.y || d.Var1}`);
    const data = distData.map(d => d.Freq);

    const ctx = document.getElementById('distributionChart').getContext('2d');
    charts['distributionChart'] = new Chart(ctx, {
        type: 'doughnut',
        data: {
            labels: labels,
            datasets: [{
                data: data,
                backgroundColor: ['#2563eb', '#6366f1', '#8b5cf6', '#d946ef'],
                borderWidth: 2,
                borderColor: '#ffffff',
                hoverOffset: 4
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            cutout: '80%',
            animation: {
                duration: 1000,
                easing: 'easeOutQuart'
            },
            plugins: {
                legend: {
                    position: 'bottom',
                    labels: { color: '#71717a', font: { family: 'Inter', size: 12 } }
                }
            }
        }
    });
}

function renderEDAChart(featureData) {
    if (charts['edaChart']) charts['edaChart'].destroy();

    let chartData = featureData.map(f => {
        let p = f.Score;
        if (p < 1e-300) p = 1e-300;
        return { feature: f.Feature, score: -Math.log10(p) };
    });
    
    chartData.sort((a, b) => b.score - a.score);

    const labels = chartData.map(d => d.feature);
    const data = chartData.map(d => d.score);

    const ctx = document.getElementById('edaChart').getContext('2d');
    
    const gradient = ctx.createLinearGradient(0, 0, 0, 300);
    gradient.addColorStop(0, '#3b82f6');
    gradient.addColorStop(1, '#1e3a8a');

    charts['edaChart'] = new Chart(ctx, {
        type: 'bar',
        data: {
            labels: labels,
            datasets: [{
                label: 'Importance (-log10 P)',
                data: data,
                backgroundColor: gradient,
                borderRadius: 4,
                borderWidth: 0
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            animation: { duration: 1000, easing: 'easeOutQuart' },
            scales: {
                y: {
                    beginAtZero: true,
                    grid: { color: '#e4e4e7', drawBorder: false },
                    ticks: { color: '#71717a', font: { family: 'Inter', size: 12 } },
                    border: { display: false }
                },
                x: {
                    grid: { display: false },
                    ticks: { color: '#71717a', maxRotation: 45, minRotation: 45, font: { family: 'Inter', size: 10 } },
                    border: { display: false }
                }
            },
            plugins: {
                legend: { display: false },
                tooltip: { 
                    backgroundColor: '#18181b', 
                    titleFont: { family: 'Inter' }, 
                    bodyFont: { family: 'Inter' },
                    padding: 8,
                    cornerRadius: 6
                }
            }
        }
    });
}

function renderConfusionMatrix(cmData) {
    const container = document.getElementById('cm-container');
    if (!cmData || cmData.length === 0) {
        container.innerHTML = '<p class="text-muted">No confusion matrix data available.</p>';
        return;
    }

    const classes = [...new Set(cmData.map(d => d.Reference))].sort((a, b) => Number(a) - Number(b));
    
    let tableHTML = '<table><thead><tr><th>Pred \\ Ref</th>';
    classes.forEach(c => tableHTML += `<th>Class ${c}</th>`);
    tableHTML += '</tr></thead><tbody>';
    
    classes.forEach(predClass => {
        tableHTML += `<tr><td class="stat-key">Class ${predClass}</td>`;
        classes.forEach(refClass => {
            const cell = cmData.find(d => String(d.Prediction) === String(predClass) && String(d.Reference) === String(refClass));
            const freq = cell ? cell.Freq : 0;
            const isDiag = String(predClass) === String(refClass);
            const style = isDiag ? 'font-weight: 600; color: #18181b;' : 'color: #71717a;';
            tableHTML += `<td style="${style}">${freq.toLocaleString()}</td>`;
        });
        tableHTML += '</tr>';
    });
    
    tableHTML += '</tbody></table>';
    container.innerHTML = tableHTML;
}

function renderClassStats(classStats) {
    const container = document.getElementById('stats-container');
    if (!classStats || classStats.length === 0 || !classStats[0]) {
        container.innerHTML = '<table><thead><tr><th>Metric</th><th>Value</th></tr></thead><tbody><tr><td colspan="2">No statistics</td></tr></tbody></table>';
        return;
    }

    let tableHTML = '<table><thead><tr><th>Metric</th><th>Value</th></tr></thead><tbody>';
    
    classStats.forEach(stat => {
        const key = stat["_row"] || stat["Class"];
        // In some cases properties sit on root (binary vs multiclass caret outputs differ)
        // Multi-class cm$byClass returns a matrix mapped to array of objects with `_row`
        // We'll iterate the object if the array elements don't strictly have `cm$byClass` properties.
        
        let valToDisplayStr = '';
        let numValForProg = NaN;

        if (stat["cm$byClass"] !== undefined) {
             // old extraction format
             numValForProg = Number(stat["cm$byClass"]);
             valToDisplayStr = numValForProg.toFixed(4);
        } else {
             // For binary cm$byClass
             Object.keys(stat).forEach(k => {
                 if(k !== "_row" && k !== "Class" && !isNaN(stat[k])) {
                     numValForProg = Number(stat[k]);
                     valToDisplayStr = numValForProg.toFixed(4);
                 }
             });
        }

        if (key && !isNaN(numValForProg)) {
            let visual = '';
            if (numValForProg >= 0 && numValForProg <= 1) {
                const percent = (numValForProg * 100).toFixed(1);
                visual = `<div class="progress-bg"><div class="progress-fill" style="width: ${percent}%;"></div></div>`;
            }
            tableHTML += `<tr><td class="stat-key">${key}</td><td class="stat-val"><div>${valToDisplayStr}</div>${visual}</td></tr>`;
        }
    });
    
    if (tableHTML.endsWith('<tbody>')) {
        // Fallback for flat dictionary (binary case without array map)
        Object.keys(classStats).forEach(k => {
            if (typeof classStats[k] === 'number' && !Array.isArray(classStats[k])) {
                 const numVal = classStats[k];
                 const visual = (numVal >= 0 && numVal <= 1) ? `<div class="progress-bg"><div class="progress-fill" style="width: ${(numVal*100).toFixed(1)}%;"></div></div>` : '';
                 tableHTML += `<tr><td class="stat-key">${k}</td><td class="stat-val"><div>${numVal.toFixed(4)}</div>${visual}</td></tr>`;
            }
        });
    }

    if (tableHTML.endsWith('<tbody>')) {
        tableHTML += '<tr><td colspan="2">No class statistics available</td></tr>';
    }
    
    tableHTML += '</tbody></table>';
    container.innerHTML = tableHTML;
}

function renderROCChart(rocData) {
    if (charts['rocChart']) charts['rocChart'].destroy();

    const ctx = document.getElementById('rocChart');
    if (!ctx) return;
    
    const context2d = ctx.getContext('2d');
    const gradient = context2d.createLinearGradient(0, 0, 0, 300);
    gradient.addColorStop(0, 'rgba(16, 185, 129, 0.25)'); 
    gradient.addColorStop(1, 'rgba(16, 185, 129, 0.05)');

    const xData = rocData.map(d => d.FPR);
    const yData = rocData.map(d => d.TPR);

    charts['rocChart'] = new Chart(context2d, {
        type: 'line',
        data: {
            labels: xData.map(v => v.toFixed(2)),
            datasets: [{
                label: 'ROC Curve (TPR)',
                data: yData,
                borderColor: '#10b981', // emerald-500
                backgroundColor: gradient,
                borderWidth: 2,
                pointRadius: 0,
                pointHoverRadius: 5,
                fill: true,
                tension: 0.1
            }, {
                label: 'Random Baseline',
                data: xData,
                borderColor: '#a1a1aa', // zinc-400
                borderWidth: 1,
                borderDash: [5, 5],
                pointRadius: 0,
                fill: false
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            animation: { duration: 800, easing: 'easeOutQuart' },
            interaction: { mode: 'nearest', intersect: false },
            scales: {
                y: {
                    title: { display: true, text: 'True Positive Rate (Sensitivity)', color: '#71717a', font: { family: 'Inter', size: 11 } },
                    min: 0, max: 1,
                    grid: { color: '#e4e4e7', drawBorder: false },
                    ticks: { color: '#71717a', font: { family: 'Inter', size: 10 } },
                    border: { display: false }
                },
                x: {
                    title: { display: true, text: 'False Positive Rate (1 - Specificity)', color: '#71717a', font: { family: 'Inter', size: 11 } },
                    grid: { display: false },
                    ticks: { color: '#71717a', font: { family: 'Inter', size: 10 }, maxRotation: 0 },
                    border: { display: false }
                }
            },
            plugins: {
                legend: { display: false },
                tooltip: { 
                    backgroundColor: '#18181b', 
                    titleFont: { family: 'Inter' }, 
                    bodyFont: { family: 'Inter' },
                    padding: 8,
                    cornerRadius: 6,
                    callbacks: {
                        label: function(context) {
                            return context.dataset.label + ': ' + context.parsed.y.toFixed(3);
                        }
                    }
                }
            }
        }
    });
}
