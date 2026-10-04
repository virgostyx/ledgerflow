# R19 consistency report: the latest run by severity, its 30-day trend, the filterable findings, the
# acknowledgement of an anomaly (with a comment) and an on-demand run.
class Accounting::ConsistencyRunsController < ApplicationController
  def index
    authorize Accounting::ConsistencyRun
    @run = Accounting::ConsistencyRun.latest_first.first
    @trend = Accounting::ConsistencyRun.where(started_at: 30.days.ago..).order(:started_at).group_by { |r| r.started_at.to_date }.map { |day, runs| [ day.to_s, open_total(runs.last) ] }
    return unless @run

    @acks = Accounting::ConsistencyAcknowledgement.where(fingerprint: @run.findings.select(:fingerprint)).index_by(&:fingerprint)
    findings = @run.findings.order(Arel.sql("CASE severity WHEN 'blocking' THEN 0 WHEN 'warning' THEN 1 ELSE 2 END"), :check_id, :id)
    findings = findings.where(severity: params[:severity]) if params[:severity].present?
    findings = findings.where(check_id: params[:check_id]) if params[:check_id].present?
    @show_acknowledged = params[:acknowledged] == "1"
    @findings = findings.reject { |f| @acks.key?(f.fingerprint) && !@show_acknowledged }
    @anomaly_tasks = feature?(:f08) ? Accounting::Task.open_ones.where(anomaly_fingerprint: @findings.map(&:fingerprint)).group(:anomaly_fingerprint).count : {}
    @checks = Accounting::Consistency::Check.registry.map { |c| [ "#{c.check_id} — #{c.title}", c.check_id ] }
  end

  def create
    authorize Accounting::ConsistencyRun
    Accounting::ConsistencyCheckJob.perform_now(ActsAsTenant.current_tenant.id)
    redirect_to accounting_consistency_runs_path, notice: "Consistency check completed."
  end

  def acknowledge
    authorize Accounting::ConsistencyRun
    ack = Accounting::ConsistencyAcknowledgement.new(fingerprint: params[:fingerprint], comment: params[:comment], user: current_user, acknowledged_at: Time.current)
    if ack.save
      redirect_to accounting_consistency_runs_path, notice: "Anomaly acknowledged."
    else
      redirect_to accounting_consistency_runs_path, alert: ack.errors.full_messages.to_sentence
    end
  end

  private

  def open_total(run) = run.counts.slice(*Accounting::ConsistencyFinding::SEVERITIES).values.sum
end
