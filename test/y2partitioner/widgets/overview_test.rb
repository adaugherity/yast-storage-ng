#!/usr/bin/env rspec
# encoding: utf-8

# Copyright (c) [2017] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com

require_relative "../test_helper"

require "cwm/rspec"
require "y2partitioner/device_graphs"
require "y2partitioner/widgets/overview"

describe Y2Partitioner::Widgets::OverviewTreePager do
  before do
    devicegraph_stub(scenario)
    Yast::ProductFeatures.Import(control_file_content)

    allow(Yast2::Popup).to receive(:show).and_return(:yes)
  end

  let(:control_file_content) do
    file_path = File.join(DATA_PATH, "control_files", control_file)
    Yast::XML.XMLToYCPFile(file_path)
  end

  subject { described_class.new("hostname") }

  let(:scenario) { "lvm-two-vgs.yml" }

  let(:control_file) { "caasp.xml" }

  let(:current_graph) { Y2Partitioner::DeviceGraphs.instance.current }

  include_examples "CWM::Pager"

  describe "#device_page" do
    let(:vg) { Y2Storage::LvmVg.find_by_vg_name(current_graph, "vg0") }

    context "when there is a page associated to the requested device" do
      let(:device) { vg }

      it "returns the page" do
        page = subject.device_page(device)
        expect(page).to be_a(CWM::Page)
        expect(page.device).to eq(device)
      end
    end

    context "when there is not a page associated to the requested device" do
      let(:device) { vg.lvm_pvs.first }

      it "returns nil" do
        page = subject.device_page(device)
        expect(page).to be_nil
      end
    end

    context "when the device is NFS" do
      let(:scenario) { "nfs1.xml" }
      let(:device) { current_graph.nfs_mounts.first }

      it "returns the general NFS page" do
        page = subject.device_page(device)
        expect(page).to be_a(CWM::Page)
        expect(page).to be_a(Y2Partitioner::Widgets::Pages::NfsMounts)
      end
    end
  end

  describe "#contents" do
    let(:scenario) { "empty-dasd-and-multipath.xml" }

    let(:widgets) { Yast::CWM.widgets_in_contents([subject]) }

    let(:overview_tree) { widgets.find { |w| w.is_a?(Y2Partitioner::Widgets::OverviewTree) } }

    let(:disks_pager) do
      system_pager = overview_tree.items.find { |i| i.page.is_a?(Y2Partitioner::Widgets::Pages::System) }
      system_pager.children.values.find { |i| i.page.is_a?(Y2Partitioner::Widgets::Pages::Disks) }
    end

    let(:disks_pages) { disks_pager.pages - [disks_pager.page] }

    let(:device_graph_page) do
      overview_tree.items.find { |i| i.page.is_a?(Y2Partitioner::Widgets::Pages::DeviceGraph) }
    end

    let(:summary_page) do
      overview_tree.items.find { |i| i.page.is_a?(Y2Partitioner::Widgets::Pages::Summary) }
    end

    let(:settings_page) do
      overview_tree.items.find { |i| i.page.is_a?(Y2Partitioner::Widgets::Pages::Settings) }
    end

    it "has a OverviewTree widget" do
      expect(overview_tree).to_not be_nil
    end

    it "has a pager for the disk devices" do
      expect(disks_pager).to_not be_nil
    end

    it "includes a 'Summary' page" do
      expect(summary_page).to_not be_nil
    end

    it "includes a 'Settings' page" do
      expect(settings_page).to_not be_nil
    end

    before do
      allow(Yast::UI).to receive(:HasSpecialWidget).with(:Graph).and_return graph_available
    end
    let(:graph_available) { true }

    context "when there are disk, dasd or multipath devices" do
      let(:scenario) { "empty-dasd-and-multipath.xml" }

      let(:md0) { "/dev/mapper/36005076305ffc73a00000000000013b4" }

      let(:md3) { "/dev/mapper/36005076305ffc73a00000000000013b5" }

      let(:dasd) { "/dev/dasdb" }

      let(:sde) { "/dev/sde" }

      it "disks pager has a page for each dasd device" do
        dasd_page = disks_pages.find { |p| p.device.name == dasd }
        expect(dasd_page).to_not be_nil
      end

      it "disks pager has a page for each multipath device" do
        md0_page = disks_pages.find { |p| p.device.name == md0 }
        expect(md0_page).to_not be_nil

        md3_page = disks_pages.find { |p| p.device.name == md3 }
        expect(md3_page).to_not be_nil
      end

      it "disks pager has a page for each disk device" do
        sde_page = disks_pages.find { |p| p.device.name == sde }
        expect(sde_page).to_not be_nil
      end

      it "disks pager has not a page for disks belonging to a multipath" do
        sda_page = disks_pages.find { |p| p.device.name == "/dev/sda" }
        expect(sda_page).to be_nil
      end
    end

    context "when there Xen devices representing disks and virtual partitions" do
      let(:scenario) { "xen-disks-and-partitions.xml" }

      it "disks pager has a page for each Xen disk" do
        page = disks_pages.find { |p| p.device.name == "/dev/xvdc" }
        expect(page).to_not be_nil
      end

      it "disks pager has a page for each Xen virtual partition" do
        page = disks_pages.find { |p| p.device.name == "/dev/xvda1" }
        expect(page).to_not be_nil

        page = disks_pages.find { |p| p.device.name == "/dev/xvda2" }
        expect(page).to_not be_nil
      end

      it "disks pager does not include an extra device to group Xen virtual partitions" do
        page = disks_pages.find { |p| p.device.name == "/dev/xvda" }
        expect(page).to be_nil
      end
    end

    context "when there are BIOS RAIDs" do
      let(:scenario) { "md-imsm1-devicegraph.xml" }

      let(:mda) { "/dev/md/a" }

      let(:mdb) { "/dev/md/b" }

      let(:sda) { "/dev/sda" }

      it "disks pager has a page for each BIOS RAID device" do
        mda_page = disks_pages.find { |p| p.device.name == mda }
        expect(mda_page).to_not be_nil

        mdb_page = disks_pages.find { |p| p.device.name == mdb }
        expect(mdb_page).to_not be_nil
      end

      it "disks pager has a page for each disk device" do
        sda_page = disks_pages.find { |p| p.device.name == sda }
        expect(sda_page).to_not be_nil
      end

      it "disks pager has not a page for disks belonging to a BIOS RAID" do
        sdb_page = disks_pages.find { |p| p.device.name == "/dev/sdb" }
        expect(sdb_page).to be_nil

        sdc_page = disks_pages.find { |p| p.device.name == "/dev/sdc" }
        expect(sdc_page).to be_nil

        sdd_page = disks_pages.find { |p| p.device.name == "/dev/sdd" }
        expect(sdd_page).to be_nil
      end
    end

    context "when there are volume groups" do
      let(:scenario) { "lvm-two-vgs.yml" }

      it "disk pager has not vg pages" do
        vg_pages = disks_pages.select { |p| p.is_a?(Y2Partitioner::Widgets::Pages::LvmVg) }
        expect(vg_pages).to be_empty
      end
    end

    context "when there are Software RAIDs" do
      let(:scenario) { "md_raid" }

      it "disk pager has not Software RAID pages" do
        md_pages = disks_pages.select { |p| p.is_a?(Y2Partitioner::Widgets::Pages::MdRaid) }
        expect(md_pages).to be_empty
      end
    end

    context "when the UI supports the Graph widget (Qt)" do
      let(:graph_available) { true }

      it "includes the 'Device Graph' page" do
        expect(device_graph_page).to_not be_nil
      end
    end

    context "when the UI does not support the Graph widget (ncurses)" do
      let(:graph_available) { false }

      it "does not include the 'Device Graph' page" do
        expect(device_graph_page).to be_nil
      end
    end
  end

  describe "#validate" do
    before do
      allow(Y2Storage::SetupChecker).to receive(:new).and_return(checker)
      allow(checker).to receive(:valid?).and_return(valid_setup)
      allow(checker).to receive(:errors).and_return(fatal_errors)

      allow(Y2Partitioner::SetupErrorsPresenter).to receive(:new).and_return(presenter)
      allow(presenter).to receive(:to_html).and_return("html representation")

      allow(Yast2::Popup).to receive(:show).and_return(user_input)
      allow(Y2Storage::UsedStorageFeatures).to receive(:new).and_return(used_features)
      allow(used_features).to receive(:feature_packages).and_return(["xfsprogs"])
      allow(Yast::PackageSystem).to receive(:CheckAndInstallPackages)
        .and_return(installed_packages)
      allow(Yast::Mode).to receive(:installation).and_return(installation)
    end

    let(:checker) { instance_double(Y2Storage::SetupChecker) }

    let(:presenter) { instance_double(Y2Partitioner::SetupErrorsPresenter) }

    let(:valid_setup) { nil }

    let(:user_input) { nil }

    let(:fatal_errors) { [] }

    let(:used_features) { Y2Storage::UsedStorageFeatures.new(current_graph) }

    let(:installed_packages) { true }

    let(:installation) { false }

    context "when the current setup is not valid" do
      context "and when errors are fatal" do
        let(:valid_setup) { false }
        let(:fatal_errors) { [double] }

        it "shows an error popup" do
          expect(Yast2::Popup).to receive(:show)
          subject.validate
        end

        it "prevents continuing" do
          expect(Yast2::Popup).to receive(:show)
          expect(subject.validate).to eq(false)
        end

        it "does not check for missing packages" do
          expect(Yast::PackageSystem).to_not receive(:CheckAndInstallPackages)
          subject.validate
        end
      end

      context "and errors are no fatal" do
        let(:valid_setup) { false }

        it "shows an error popup" do
          expect(Yast2::Popup).to receive(:show)
          subject.validate
        end

        context "and the user accepts to continue" do
          let(:user_input) { :yes }

          it "returns true" do
            expect(subject.validate).to eq(true)
          end

          it "checks for needed packages" do
            expect(Yast::PackageSystem).to receive(:CheckAndInstallPackages)
              .with(["xfsprogs"])
            subject.validate
          end

          context "but the user refuses to install them " do
            let(:installed_packages) { false }

            it "returns false" do
              expect(subject.validate).to eq(false)
            end
          end

          context "but running on installation" do
            let(:installation) { true }

            it "does not check for missing packages" do
              expect(Yast::PackageSystem).to_not receive(:CheckAndInstallPackages)
              subject.validate
            end
          end
        end

        context "and the user declines to continue" do
          let(:user_input) { :no }

          it "returns false" do
            expect(subject.validate).to eq(false)
          end

          it "does not check for missing packages" do
            expect(Yast::PackageSystem).to_not receive(:CheckAndInstallPackages)
            subject.validate
          end
        end
      end
    end

    context "when the current setup is valid" do
      let(:valid_setup) { true }

      it "does not show an error popup" do
        expect(Yast2::Popup).to_not receive(:show)
        subject.validate
      end

      it "returns true" do
        expect(subject.validate).to eq(true)
      end

      it "checks for needed packages" do
        expect(Yast::PackageSystem).to receive(:CheckAndInstallPackages)
          .with(["xfsprogs"])
        subject.validate
      end

      context "but the user refuses to install them " do
        let(:installed_packages) { false }

        it "returns false" do
          expect(subject.validate).to eq(false)
        end
      end

      context "but running on installation" do
        let(:installation) { true }

        it "does not check for missing packages" do
          expect(Yast::PackageSystem).to_not receive(:CheckAndInstallPackages)
          subject.validate
        end
      end
    end
  end
end
