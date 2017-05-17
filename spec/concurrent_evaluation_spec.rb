describe IOEventLoop::ConcurrentEvaluation do
  let(:loop) { IOEventLoop.new }

  describe "#await_result" do
    subject { concurrent_evaluation.await_result(&with_result) }

    let(:concurrent_evaluation) { loop.concurrent_proc(&wait_proc).call_detached }
    let(:with_result) { nil }
    let(:result) { :result }

    it_behaves_like "awaiting the result of a deferred evaluation" do
      let(:wait_proc) { proc do
        loop.concurrent_proc{ loop.wait evaluation_time; result }.call_detached.await_result wait_options
      end }
    end

    context "when it evaluates to a result" do
      let(:wait_proc) { proc{ result } }

      before { expect(concurrent_evaluation).not_to be_concluded }
      after { expect(concurrent_evaluation).to be_concluded }

      it { is_expected.to be :result }

      context "when requesting the result a second time" do
        before { concurrent_evaluation.await_result }
        it { is_expected.to be :result }
      end

      context "when the result is an array" do
        let(:result) { %i(a b c) }
        it { is_expected.to eq %i(a b c) }
      end

      context "when a block to do something with the result is given" do
        context "when transforming to a non-error value" do
          let(:with_result) { proc{ |result| "transformed #{result} to result" } }
          it { is_expected.to eq "transformed result to result" }
        end

        context "when transforming to an error value" do
          let(:with_result) { proc{ |result| RuntimeError.new("transformed #{result} to error") } }
          it { is_expected.to raise_error RuntimeError, 'transformed result to error' }
        end
      end
    end

    context "when it evaluates to an error" do
      let(:wait_proc) { proc{ raise 'error' } }

      before { expect(concurrent_evaluation).not_to be_concluded }
      after { expect(concurrent_evaluation).to be_concluded }

      it { is_expected.to raise_error RuntimeError, 'error' }

      context "when requesting the result a second time" do
        before { concurrent_evaluation.await_result rescue nil }
        it { is_expected.to raise_error RuntimeError, 'error' }
      end

      context "when a block to do something with the result is given" do
        context "when transforming to a non-error value" do
          let(:with_result) { proc{ |result| "transformed #{result} to result" } }
          it { is_expected.to eq "transformed error to result" }
        end

        context "when transforming to an error value" do
          let(:with_result) { proc{ |result| RuntimeError.new("transformed #{result} to error") } }
          it { is_expected.to raise_error RuntimeError, 'transformed error to error' }
        end
      end
    end

    context "when getting the result of a concurrent proc from two other ones" do
      let!(:concurrent_evaluation) { loop.concurrent_proc{ loop.wait(0.0001); :result }.call_detached }
      let!(:concurrent_evaluation1) { loop.concurrent_proc{ concurrent_evaluation.await_result }.call_detached }
      let!(:concurrent_evaluation2) { loop.concurrent_proc{ concurrent_evaluation.await_result within: 0.00005, timeout_result: :timeout_result }.call_detached }

      it { is_expected.to be :result }
      after { expect(concurrent_evaluation1.await_result).to be :result }
      after { expect(concurrent_evaluation2.await_result).to be :timeout_result }
    end
  end

  describe "#cancel" do
    before { expect(concurrent_evaluation).not_to be_concluded }
    after { expect(concurrent_evaluation).to be_concluded }

    context "when doing it before requesting the result" do
      subject { concurrent_evaluation.cancel *reason }

      let(:concurrent_evaluation) { loop.concurrent_proc{ :result }.call_detached }

      context "when giving no explicit reason" do
        let(:reason) { nil }
        it { is_expected.to be :cancelled }
        after { expect{ concurrent_evaluation.await_result }.to raise_error IOEventLoop::CancelledError, "evaluation cancelled" }
      end

      context "when giving a reason" do
        let(:reason) { 'cancel reason' }
        it { is_expected.to be :cancelled }
        after { expect{ concurrent_evaluation.await_result }.to raise_error IOEventLoop::CancelledError, "cancel reason" }
      end
    end

    context "when doing it after requesting the result" do
      subject { loop.concurrent_proc{ concurrent_evaluation.cancel *reason }.call }

      let(:concurrent_evaluation) { loop.concurrent_proc{ loop.wait(0.0001) }.call_detached }

      context "when giving no explicit reason" do
        let(:reason) { nil }
        it { is_expected.to be :cancelled }
        after { expect{ concurrent_evaluation.await_result }.to raise_error IOEventLoop::CancelledError, "evaluation cancelled" }
      end

      context "when giving a reason" do
        let(:reason) { 'cancel reason' }
        it { is_expected.to be :cancelled }
        after { expect{ concurrent_evaluation.await_result }.to raise_error IOEventLoop::CancelledError, "cancel reason" }
      end
    end

    context "when cancelling after it is already evaluated" do
      subject { concurrent_evaluation.cancel }

      let(:concurrent_evaluation) { loop.concurrent_proc{ :result }.call_detached }
      before { concurrent_evaluation.await_result }

      it { is_expected.to raise_error IOEventLoop::Error, "already concluded" }
    end

    context "when concluding an evaluation from a nested proc" do
      subject { concurrent_evaluation.await_result }

      let!(:concurrent_evaluation) { loop.concurrent_proc do
        loop.concurrent_proc do
          loop.concurrent_proc do
            concurrent_evaluation.conclude_with :cancelled
          end.call_detached

          # The return value of this concurrent proc would be used as a
          # proc in the scheduled concurrent block of the outer concurrent
          # proc unless it is not properly cancelled.
          :trouble_maker
        end.call_detached.await_result
      end.call_detached }

      it { is_expected.not_to raise_error }
    end
  end

  describe "#manually_resume!" do
    subject { concurrent_evaluation.await_result }

    let!(:concurrent_evaluation) { loop.concurrent_proc{ loop.await_manual_resume! }.call_detached }

    before { loop.concurrent_proc do
      loop.wait 0.0001
      concurrent_evaluation.manually_resume! *result
    end.call_detached }

    context "when given no result" do
      let(:result) { [] }
      it { is_expected.to eq nil }
    end

    context "when given a result" do
      let(:result) { :result }
      it { is_expected.to eq :result }
    end
  end
end